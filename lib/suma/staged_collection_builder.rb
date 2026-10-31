# frozen_string_literal: true

require "metanorma"
require "yaml"
require "fileutils"

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
    # entries, so children cannot race. (a data-declaring initializer)
    def initialize(collection_config_path:, output_directory:, coverpage: nil,
                   store_dir: nil, formats: %i[xml html], no_valid: false,
                   workers: 1, batch_size: DEFAULT_BATCH_SIZE) # rubocop:disable Metrics/ParameterLists
      @config_path = collection_config_path
      @config_dir = File.dirname(File.expand_path(collection_config_path))
      @output_directory = output_directory
      @coverpage = coverpage
      @store_dir = store_dir || File.join(output_directory, STORE_DIRNAME)
      @formats = formats
      @no_valid = no_valid
      @workers = [workers.to_i, 1].max
      @batch_size = [batch_size.to_i, 1].max
    end

    def build
      FileUtils.mkdir_p(@output_directory)
      FileUtils.mkdir_p(@store_dir)
      members = collection_members
      Utils.log "[staged] #{members.size} members; workers: #{@workers}; " \
                "batch size: #{@batch_size}; store: #{@store_dir}"
      if @workers == 1
        members.each_with_index { |member, i| stage_member(member, i) }
      else
        stage_parallel(members)
      end
      reinflate(members)
    end

    private

    # Batch the members and run +@workers+ renderer child processes
    # concurrently. Each batch file carries fully-rendered single-member
    # manifests; children claim batches through O_EXCL markers, so a slow
    # worker never starves. One Metanorma boot amortises over
    # +@batch_size+ members (the boot dominates small members), and each
    # child exit hands its memory back to the OS. Members write disjoint,
    # identifier-keyed store entries, so concurrent children cannot race;
    # sectionsplit only happens at reinflate (a single sequential pass).
    def stage_parallel(members)
      paths, count = write_batch_files(members)
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
      <<~RUBY
        require "yaml"
        require "fileutils"
        require "metanorma"
        config_dir, batch_count, store_dir, out_dir, no_valid = ARGV
        count = Integer(batch_count)
        claimed = 0
        loop do
          idx = (0...count).find do |i|
            begin
              File.open(File.join(config_dir, "._suma_batch_\#{i}.claim"),
                        File::RDWR | File::CREAT | File::EXCL) {}
              true
            rescue Errno::EEXIST
              false
            end
          end
          break unless idx

          manifests = Marshal.load(File.binread(File.join(
            config_dir, "._suma_batch_\#{idx}.bin")))
          manifests.each_with_index do |manifest, j|
            one_path = File.join(config_dir,
                                 "._suma_staged_b\#{idx}_\#{j}.yml")
            out = File.join(out_dir, "._staged_out_b\#{idx}_\#{j}")
            t0 = Time.now
            begin
              File.write(one_path, YAML.dump(manifest))
              # The artefact store keys on the rendered document's own
              # docid, while the parent reinflates by the docref
              # identifier; members whose document docid differs from the
              # docref (docrefs carrying metanorma's GUID marker) were
              # therefore unrecoverable ("no stored artefact"). Alias the
              # artefacts this render produced under the docref slug too.
              # Shape: single_member_manifest => {"manifest" =>
              #   {"manifest" => [{"docref" => [dr]}]}}.
              member_id = manifest.dig("manifest", "manifest", 0, "docref", 0, "identifier")
              id_slug = member_id.to_s
                .gsub(/[^A-Za-z0-9._-]+/, "-").gsub(/-{2,}/, "-")
                .gsub(/\A-|-\z/, "")
              semantics_before = Dir.children(store_dir)
                .select { |f| f.end_with?(".semantic.xml") }
              compile = { install_fonts: false }
              compile[:novalid] = true if no_valid == "1"
              Metanorma::Collection.parse(one_path).render(
                format: [:xml], output_folder: out,
                preserve_unresolved: true, artifact_store_dir: store_dir,
                compile: compile,
              )
              unless id_slug.empty?
                produced = Dir.children(store_dir).select do |f|
                  f.end_with?(".semantic.xml")
                end - semantics_before
                produced.each do |f|
                  if (m = f.match(/\A(.*).([0-9a-f]+).semantic.xml\z/))
                    alias_name = "\#{id_slug}.\#{m[2]}.semantic.xml"
                    alias_path = File.join(store_dir, alias_name)
                    FileUtils.cp(File.join(store_dir, f), alias_path)
                  end
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
    def reinflate(members)
      reinf_dir = File.join(@output_directory, "_staged_reinflate")
      FileUtils.mkdir_p(reinf_dir)
      docrefs = stored_docrefs(members, reinf_dir)
      reinf_path = File.join(reinf_dir, "reinflate.yml")
      File.write(reinf_path,
                 base_manifest.merge("manifest" => collection_manifest(docrefs)).to_yaml)
      Utils.log "[staged] reinflating #{docrefs.size} stored members -> " \
                "#{@output_directory}"
      run_render(
        manifest_path: reinf_path,
        opts: { format: @formats, output_folder: @output_directory,
                reinflate: true, coverpage: @coverpage,
                compile: compile_flags }.compact,
      )
    end

    def compile_flags
      { install_fonts: false }.tap do |flags|
        flags[:novalid] = true if @no_valid
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
