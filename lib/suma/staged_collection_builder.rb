# frozen_string_literal: true

require "metanorma"
require "yaml"
require "fileutils"
require "pathname"

module Suma
  # Memory-bounded, resumable staged collection build (metanorma/suma#94).
  #
  # A normal collection build renders every member document in one OS process, so
  # peak memory accumulates across the whole collection and a large collection
  # (e.g. the STEP SRL) OOMs. This builder instead:
  #
  #   1. compiles each member in its OWN fresh OS process, preserving that
  #      member's unresolved cross-document references as stubs and writing the
  #      stub-bearing Semantic XML + anchors to a durable content-addressed store
  #      (the metanorma engine's +preserve_unresolved:+ / +artifact_store_dir:+
  #      render options, metanorma/metanorma#576);
  #   2. runs those per-member processes SEQUENTIALLY by default; with
  #      +workers+ > 1, batches of members are rendered by that many child
  #      processes concurrently (safe: members write disjoint store entries,
  #      and sectionsplit happens only in the sequential reinflate pass); each
  #      process exit hands its memory back to the OS, so peak memory stays
  #      bounded by workers x one member; then
  #   3. REINFLATES: a final pass assembles a manifest of the stored stubs and
  #      resolves them into real cross-document links (+reinflate:+), producing
  #      the same output an all-present build would.
  #
  # The empirical case (metanorma/metanorma#576): on the real SRL a single-process
  # build peaks ~4.1 GB and OOMs; each member compiled in isolation peaks ~1 GB,
  # so process isolation is a ~4x peak reduction that converts the OOM into a
  # bounded footprint.
  #
  # This is opt-in; +Suma::Processor+ uses the normal single-process build unless
  # staging is requested.
  class StagedCollectionBuilder
    STORE_DIRNAME = ".metanorma-collection-cache"

    # Members rendered per child process: one Metanorma boot amortised over
    # a batch of small members keeps boot cost under a few percent.
    DEFAULT_BATCH_SIZE = 25

    # +collection_config_path+ is the emitted collection manifest (the same
    # +collection-output.yaml+ the normal build renders). Member filerefs are
    # relative to its directory, so all per-member manifests are written there.
    # +workers+ > 1 runs that many renderer processes concurrently over batches
    # of +batch_size+ members; members write disjoint, identifier-keyed store
    # entries, so children cannot race. +shard+ is an [index, total] pair:
    # only members whose position satisfies +index % total+ are staged and
    # reinflation is skipped, so disjoint shards of one collection can render
    # concurrently in separate build runs into a shared store. +isolate+ is
    # a fileref slug with the same shard semantics for a single member.
    # (a data-declaring initializer)
    def initialize(collection_config_path:, output_directory:, coverpage: nil,
                   store_dir: nil, formats: %i[xml html], no_valid: false,
                   unresolved_eref_markers: false,
                   workers: 1, batch_size: DEFAULT_BATCH_SIZE,
                   shard: nil, isolate: nil, reinflate_shard: nil) # rubocop:disable Metrics/ParameterLists
      @config_path = collection_config_path
      @config_dir = File.dirname(File.expand_path(collection_config_path))
      @output_directory = output_directory
      @coverpage = coverpage
      @store_dir = store_dir || File.join(output_directory, STORE_DIRNAME)
      @formats = formats
      @no_valid = no_valid
      @unresolved_eref_markers = unresolved_eref_markers
      @workers = [workers.to_i, 1].max
      @batch_size = [batch_size.to_i, 1].max
      @shard = shard
      @isolate = isolate
      @reinflate_shard = reinflate_shard
    end

    def build
      FileUtils.mkdir_p(@output_directory)
      FileUtils.mkdir_p(@store_dir)
      members = collection_members
      staged = staged_selection(members)
      Utils.log shard_log(staged.size, members.size)
      stage_members(staged)
      return if @shard || @isolate

      reinflate(reinflate_selection(members), members)
    end

    private

    # The staged slice of the collection: an isolate selection wins over a
    # modulo shard when both are given.
    def staged_selection(members)
      @isolate ? isolate_members(members) : shard_members(members)
    end

    # Render the staged members, serially or across the worker pool.
    def stage_members(staged)
      if @workers == 1
        unstaged_members(staged).each_with_index { |member, i| stage_member(member, i) }
      else
        stage_parallel(staged)
      end
    end

    # The reinflated slice: all members unless a reinflate shard is given,
    # in which case only the members matching +index % total+ render into
    # the output directory. Disjoint reinflate slices of one collection can
    # run as parallel build jobs over the same store: each renders its own
    # members' sections, cross-references resolve through the restored
    # anchors of the whole store, and the written files are disjoint.
    def reinflate_selection(members)
      return members unless @reinflate_shard

      index, total = @reinflate_shard
      members.each_with_index.filter_map do |member, position|
        member if (position % total) == index
      end
    end

    # A shard stages the members whose position in the member order matches
    # +index % total+; the full member list is unchanged.
    def shard_members(members)
      return members unless @shard

      index, total = @shard
      members.each_with_index.filter_map do |member, position|
        member if (position % total) == index
      end
    end

    # Isolation stages the single member whose fileref path contains the
    # +isolate+ slug (e.g. a mega-member that needs a whole runner to
    # itself, away from sibling workers), and skips reinflation like a
    # shard. Empty selection means the slug matched nothing, which is a
    # caller error worth failing on rather than silently rendering
    # nothing.
    def isolate_members(members)
      staged = members.select do |member|
        File.basename(member["fileref"]).include?(@isolate)
      end
      return staged unless staged.empty?

      raise ArgumentError,
            "--staged-shard-isolate matched no member for #{@isolate.inspect}"
    end

    def shard_log(staged_count, total_count)
      line = "[staged] #{total_count} members; workers: #{@workers}; " \
             "batch size: #{@batch_size}; store: #{@store_dir}"
      if @isolate
        return "#{line}; isolate #{@isolate.inspect}: staging " \
               "#{staged_count}, skipping reinflate"
      end
      return line unless @shard

      "#{line}; shard #{@shard[0]}/#{@shard[1]}: staging #{staged_count}, " \
        "skipping reinflate"
    end

    # Members already present in the store (their docref-slug artefact
    # exists) are not re-rendered: an interrupted or repeated build over
    # a warm store goes straight to reinflate, so the assembly pass costs
    # minutes instead of re-rendering the whole collection.
    def unstaged_members(members)
      members.reject do |member|
        identifier = member["identifier"]
        stored = identifier && stored_semantic(identifier)
        Utils.log "[staged] stored, skipping #{identifier}" if stored
        stored
      end
    end

    # Batch the members and run +@workers+ renderer child processes
    # concurrently. Each batch file carries fully-rendered single-member
    # manifests; children claim batches through O_EXCL markers, so a slow
    # worker never starves. One Metanorma boot amortises over
    # +@batch_size+ members (the boot dominates small members), and each
    # child exit hands its memory back to the OS. Members write disjoint,
    # identifier-keyed store entries, so concurrent children cannot race;
    # sectionsplit only happens at reinflate (a single sequential pass).
    def stage_parallel(members)
      paths, count = write_batch_files(unstaged_members(members))
      run_batch_workers(count)
    ensure
      remove_batch_files(paths, count)
    end

    def write_batch_files(members)
      batches = batch_manifests(members)
      paths = write_batch_bins(batches)
      Utils.log "[staged] #{batches.size} batches over #{@workers} workers"
      [paths, batches.size]
    end

    def batch_manifests(members)
      members.each_slice(@batch_size).map do |slice|
        slice.map do |member|
          base_manifest.merge("manifest" => collection_manifest([member]))
        end
      end
    end

    def write_batch_bins(batches)
      batches.map.with_index do |batch, i|
        path = File.join(@config_dir, "._suma_batch_#{i}.bin")
        File.binwrite(path, Marshal.dump(batch))
        path
      end
    end

    def run_batch_workers(count)
      children = Array.new([@workers, count].min) do
        Process.spawn(RbConfig.ruby, "-e", child_script, @config_dir,
                      count.to_s, @store_dir, @output_directory,
                      @no_valid ? "1" : "0", chdir: @config_dir)
      end
      failed = children
        .filter_map { |pid| Process.waitpid2(pid) }
        .map(&:last).reject(&:success?).size
      return if failed.zero?

      raise "[staged] #{failed} of #{@workers} batch workers failed; " \
            "see the worker output above"
    end

    def remove_batch_files(paths, count)
      paths&.each { |path| FileUtils.rm_f(path) }
      (0...(count || 0)).each do |i|
        FileUtils.rm_f(File.join(@config_dir, "._suma_batch_#{i}.claim"))
      end
    end

    # Child renderer: claims and renders batches until none remain. The
    # Metanorma boot is paid once per child, and GC runs between members to
    # bound the heap. Any render failure exits nonzero and fails the build.
    def child_script
      <<~'RUBY'
        require "yaml"
        require "fileutils"
        require "metanorma"
        config_dir, batch_count, store_dir, out_dir, no_valid = ARGV
        count = Integer(batch_count)
        claimed = 0
        loop do
          idx = (0...count).find do |i|
            begin
              File.open(File.join(config_dir, "._suma_batch_#{i}.claim"),
                        File::RDWR | File::CREAT | File::EXCL) {}
              true
            rescue Errno::EEXIST
              false
            end
          end
          break unless idx

          manifests = Marshal.load(File.binread(File.join(
            config_dir, "._suma_batch_#{idx}.bin")))
          manifests.each_with_index do |manifest, j|
            one_path = File.join(config_dir,
                                 "._suma_staged_b#{idx}_#{j}.yml")
            out = File.join(out_dir, "._staged_out_b#{idx}_#{j}")
            t0 = Time.now
            begin
              File.write(one_path, YAML.dump(manifest))
              # The artefact store keys on the rendered document's own
              # docid, while the parent reinflates by the docref
              # identifier; members whose document docid differs from the
              # docref (docrefs carrying metanorma's GUID marker) were
              # therefore unrecoverable ("no stored artefact"). Alias the
              # artefacts keyed by the render's own bibdata keys under the
              # docref slug too. Shape: single_member_manifest =>
              # {"manifest" => {"manifest" => [{"docref" => [dr]}]}}.
              member_id = manifest.dig("manifest", "manifest", 0, "docref", 0, "identifier")
              id_slug = member_id.to_s
                .gsub(/[^A-Za-z0-9._-]+/, "-").gsub(/-{2,}/, "-")
                .gsub(/\A-|-\z/, "")
              compile = { install_fonts: false }
              compile[:novalid] = true if no_valid == "1"
              collection = Metanorma::Collection.parse(one_path)
              collection.render(
                format: [:xml], output_folder: out,
                preserve_unresolved: true, artifact_store_dir: store_dir,
                compile: compile,
              )
              unless id_slug.empty?
                # Alias strictly from the collection's own bibdata keys:
                # they are the docids this member's render stored under.
                # A produced-files delta is not safe here - with
                # concurrent workers another child's render lands in the
                # shared store mid-flight, and a delta would alias other
                # members' documents under this docref (suma#167).
                (collection.bibdatas || {}).keys.each do |key|
                  src_slug = key.to_s
                    .gsub(/[^A-Za-z0-9._-]+/, "-").gsub(/-{2,}/, "-")
                    .gsub(/\A-|-\z/, "")
                  next if src_slug.empty? || src_slug == id_slug

                  Dir[File.join(store_dir,
                                "#{src_slug}.*.semantic.xml")].each do |f|
                    alias_name = f.sub(
                      %r{/#{Regexp.escape(src_slug)}.},
                      "/#{id_slug}.",
                    )
                    FileUtils.cp(f, alias_name)
                  end
                end
              end

              # The corpus manifests carry no bibdata, so bibdatas is
              # empty and the loop above never runs (suma#181): the
              # artefacts stay keyed under the document's own docid and
              # reinflate - looking up by the docref identifier - finds
              # nothing on a cold store ("no stored artefact"). metanorma
              # resolves every manifest identifier to the document docid
              # during populate and records the mapping on the manifest
              # itself (identifier_aliases, raw -> resolved). That map is
              # the child's own post-render collection - reading it is
              # race-free per the suma#167 discipline.
              aliases = begin
                collection.manifest.identifier_aliases || {}
              rescue NoMethodError
                {}
              end
              aliases.each do |original, resolved|
                src = resolved.to_s
                  .gsub(/[^A-Za-z0-9._-]+/, "-").gsub(/-{2,}/, "-")
                  .gsub(/\A-|-\z/, "")
                dst = original.to_s
                  .gsub(/[^A-Za-z0-9._-]+/, "-").gsub(/-{2,}/, "-")
                  .gsub(/\A-|-\z/, "")
                next if src.empty? || dst.empty? || src == dst

                Dir[File.join(store_dir, "#{src}.*.semantic.xml")].each do |f|
                  FileUtils.cp(
                    f, f.sub(%r{/#{Regexp.escape(src)}\.}, "/#{dst}."),
                  )
                end
              end
              warn format("[staged worker %d] batch %d/%d member %d OK (%ds)",
                          Process.pid, idx + 1, count, j, Time.now - t0)
            ensure
              File.unlink(one_path) rescue nil
              FileUtils.rm_rf(out) rescue nil
              GC.start
            end
          end
          claimed += 1
        end
        exit 1 if claimed.zero? && count.positive?
      RUBY
    end

    def manifest
      @manifest ||= YAML.load_file(@config_path)
    end

    # Every document member of the manifest tree, in order: any node carrying a
    # file reference (+fileref+ or legacy +file+) that is not an attachment.
    def collection_members
      members = []
      walk_members(manifest["manifest"]) { |member| members << member }
      members
    end

    def walk_members(node, &block)
      case node
      when Array then node.each { |child| walk_members(child, &block) }
      when Hash then walk_member_hash(node, &block)
      end
    end

    def walk_member_hash(node, &block)
      ref = node["fileref"] || node["file"]
      ref && !truthy?(node["attachment"]) and
        yield({ "fileref" => ref, "identifier" => node["identifier"],
                "sectionsplit" => node["sectionsplit"] }.compact)
      node.each_value { |value| walk_members(value, &block) }
    end

    # Stage one member in its own process: a single-member manifest rendered with
    # preserve + store. Written beside the collection config so relative filerefs
    # resolve; removed afterwards.
    def stage_member(member, idx)
      one_path = File.join(@config_dir, "._suma_staged_#{idx}.yml")
      File.write(one_path, single_member_manifest(member).to_yaml)
      out = File.join(@output_directory, "._staged_out_#{idx}")
      run_render(
        manifest_path: one_path,
        opts: { format: [:xml], output_folder: out,
                preserve_unresolved: true, artifact_store_dir: @store_dir,
                compile: compile_flags },
      )
    ensure
      FileUtils.rm_f(one_path)
      FileUtils.rm_rf(File.join(@output_directory, "._staged_out_#{idx}"))
    end

    # Assemble a manifest of the stored stubs and reinflate them into the site.
    # The original manifest tree is preserved (nested collections,
    # attachments, per-member sectionsplit) with each member entry swapped
    # for its stored stub; the render resolves paths against the
    # reinflate manifest's own directory, so every path the render reads
    # is absolutized against the collection root (suma#168, suma#169).
    def reinflate(render_members, all_members = render_members)
      reinf_dir = File.join(@output_directory, "_staged_reinflate")
      FileUtils.mkdir_p(reinf_dir)
      # Stub every member: the render passes read each member's stored
      # file for the anchors and cross-references, whatever this run is
      # going to render. A reinflate shard additionally restricts the
      # rendered members; sibling runs over the same store render the
      # rest.
      docrefs = stored_docrefs(all_members, reinf_dir)
      write_reinflate_manifest(docrefs, reinf_dir)
      run_render(manifest_path: File.join(reinf_dir, "reinflate.yml"),
                 opts: reinflate_render_options(render_members))
    end

    def write_reinflate_manifest(docrefs, reinf_dir)
      rebuilt = with_stubbed_members(manifest["manifest"], docrefs, [0],
                                     reinf_dir)
      reinf_path = File.join(reinf_dir, "reinflate.yml")
      File.write(reinf_path,
                 base_manifest.merge("manifest" => rebuilt).to_yaml)
      Utils.log "[staged] reinflating #{docrefs.size} stored members -> " \
                "#{@output_directory}"
    end

    def reinflate_render_options(render_members = nil)
      opts = {
        format: @formats,
        output_folder: File.expand_path(@output_directory),
        reinflate: true,
        coverpage: @coverpage && File.expand_path(@coverpage, @config_dir),
        compile: compile_flags,
      }
      if @reinflate_shard && render_members
        opts[:only_members] = render_members.filter_map { |m| m["identifier"] }
      end
      opts.compact
    end

    # Deep-copy the manifest tree, replacing each member entry (same
    # predicate and pre-order as collection_members) with its stub docref,
    # and absolutizing non-member filerefs (attachments) against the
    # collection root. A member entry referencing a nested collection
    # manifest additionally has that manifest's attachment docrefs grafted
    # beside the stub: metanorma grafts nested manifests only around a
    # surviving referencing entry, which the stub is not, so the reinflate
    # manifest has to carry the attachment entries itself (suma#169).
    def with_stubbed_members(node, docrefs, counter, reinf_dir)
      case node
      when Array
        node.flat_map do |child|
          rewritten = with_stubbed_members(child, docrefs, counter, reinf_dir)
          [rewritten, *carried_attachments(child, reinf_dir)]
        end
      when Hash
        with_stubbed_members_hash(node, docrefs, counter, reinf_dir)
      else
        node
      end
    end

    def with_stubbed_members_hash(node, docrefs, counter, reinf_dir)
      rewritten = node.dup
      rewritten.each_key do |key|
        rewritten[key] =
          rewrite_entry_value(key, rewritten[key], docrefs, counter, reinf_dir)
      end
      stub_for(rewritten, docrefs, counter) || rewritten
    end

    def rewrite_entry_value(key, value, docrefs, counter, reinf_dir)
      if %w[file fileref].include?(key) && value &&
          !Pathname.new(value).absolute?
        File.expand_path(value, @config_dir)
      else
        with_stubbed_members(value, docrefs, counter, reinf_dir)
      end
    end

    # The attachment docrefs a member entry's nested collection manifest
    # declares, as one grouping node to graft after the member's stub.
    # The filerefs are re-expressed relative to +reinf_dir+ (where the
    # reinflate manifest is written), so the render resolves each source
    # and derives the destination path the plain build does: the leading
    # ../ climb is truncated into the output directory.
    def carried_attachments(member, reinf_dir)
      return [] unless member.is_a?(Hash) && member_entry?(member)

      ref = member["fileref"] || member["file"]
      return [] unless manifest_ref?(ref)

      attachments = []
      collect_nested_attachments(ref, @config_dir, attachments, reinf_dir)
      return [] if attachments.empty?

      [{ "level" => "attachments", "title" => "Attachments",
         "identifier" => [member["identifier"], "attachments"]
           .compact.join("-"),
         "docref" => attachments }]
    end

    def collect_nested_attachments(ref, dir, out, reinf_dir)
      path = File.expand_path(ref, dir)
      tree = nested_manifest_tree(path) or return
      collect_attachments(tree, File.dirname(path), out, reinf_dir)
    end

    # Every attachment docref of a (nested) manifest tree, in declaration
    # order: attachment entries are carried with their fileref re-expressed
    # relative to +reinf_dir+; entries referencing further nested manifests
    # recurse into those files; every other entry is walked in place.
    def collect_attachments(node, dir, out, reinf_dir)
      case node
      when Array
        node.each { |child| collect_attachments(child, dir, out, reinf_dir) }
      when Hash
        collect_attachments_hash(node, dir, out, reinf_dir)
      end
    end

    def collect_attachments_hash(node, dir, out, reinf_dir)
      dispatch_attachments(node, dir, out, reinf_dir)
      node.each_value { |value| collect_attachments(value, dir, out, reinf_dir) }
    end

    # An attachment entry is carried with its fileref re-expressed; an
    # entry referencing a further nested manifest recurses into that file.
    def dispatch_attachments(node, dir, out, reinf_dir)
      ref = node["fileref"] || node["file"]
      return unless ref

      if truthy?(node["attachment"])
        out << carried_attachment_entry(node, dir, reinf_dir)
      elsif manifest_ref?(ref)
        collect_nested_attachments(ref, dir, out, reinf_dir)
      end
    end

    def carried_attachment_entry(node, dir, reinf_dir)
      carried = node.dup
      %w[fileref file].each do |key|
        next unless carried[key]

        carried[key] = reinf_relative(File.expand_path(carried[key], dir),
                                      reinf_dir)
      end
      carried
    end

    def reinf_relative(path, reinf_dir)
      base = Pathname.new(File.expand_path(reinf_dir))
      Pathname.new(File.expand_path(path)).relative_path_from(base).to_s
    end

    def manifest_ref?(ref)
      /\.ya?ml\z/.match?(ref)
    end

    # The manifest tree of a nested collection manifest file: its +manifest+
    # node, the same node metanorma grafts at render time. A file that is
    # not a collection manifest carries nothing.
    def nested_manifest_tree(path)
      return unless File.file?(path)

      nested = YAML.load_file(path)
      tree = nested.is_a?(Hash) ? nested["manifest"] : nil
      tree if tree.is_a?(Hash) || tree.is_a?(Array)
    end

    def stub_for(node, docrefs, counter)
      return unless member_entry?(node)

      index = counter[0]
      counter[0] += 1
      docrefs[index]
    end

    def member_entry?(node)
      (node["fileref"] || node["file"]) && !truthy?(node["attachment"])
    end

    def compile_flags
      { install_fonts: false }.tap do |flags|
        flags[:novalid] = true if @no_valid
        flags[:unresolved_eref_markers] = true if @unresolved_eref_markers
      end
    end

    # Copy each member's stored stub into +dir+ and return docref entries pointing
    # at the copies, keyed by real docid (as the store keys them).
    def stored_docrefs(members, dir)
      members.map.with_index do |member, i|
        stored = stored_semantic(member["identifier"]) or
          raise "[staged] no stored artefact for #{member['identifier'].inspect}"
        name = "member_#{i}.xml"
        FileUtils.cp(stored, File.join(dir, name))
        dr = { "fileref" => name, "identifier" => member["identifier"] }
        dr["sectionsplit"] = true if truthy?(member["sectionsplit"])
        dr
      end
    end

    # A minimal single-member manifest reusing the collection's directives and
    # bibdata, so the isolated render carries the right collection identity.
    def single_member_manifest(member)
      base_manifest.merge("manifest" => collection_manifest([member]))
    end

    def collection_manifest(docrefs)
      { "level" => "collection", "title" => "Collection",
        "manifest" => [{ "level" => "subcollection", "title" => "Members",
                         "docref" => docrefs }] }
    end

    def base_manifest
      { "directives" => manifest["directives"] || ["documents-inline"],
        "bibdata" => manifest["bibdata"] }.compact
    end

    def stored_semantic(identifier)
      Dir[File.join(@store_dir, "#{slug(identifier)}.*.semantic.xml")]
        .max_by { |f| File.mtime(f) }
    end

    # Mirrors the store's filename slug (metanorma ArtifactStore#slug).
    def slug(identifier)
      identifier.to_s.gsub(/[^A-Za-z0-9._-]+/, "-")
        .gsub(/-{2,}/, "-").gsub(/\A-|-\z/, "")
    end

    # Render a manifest in a FRESH child process so its memory is reclaimed on
    # exit. Under +bundle exec+, the child inherits the bundle. Raises on failure.
    def run_render(manifest_path:, opts:)
      script = <<~RUBY
        require "metanorma"
        opts = Marshal.load(STDIN.read)
        Metanorma::Collection.parse(#{manifest_path.inspect}).render(opts)
      RUBY
      IO.popen([RbConfig.ruby, "-e", script], "wb") do |io|
        io.write(Marshal.dump(opts))
        io.close_write
      end
      return if $?.success?

      raise "[staged] render subprocess failed for #{manifest_path}"
    end

    def truthy?(val)
      [true, "true"].include?(val)
    end
  end
end
