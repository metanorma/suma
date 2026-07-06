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
  #   2. runs those per-member processes SEQUENTIALLY (never in parallel --
  #      parallelism reintroduces the cross-linking / sectionsplit races that are
  #      deliberately avoided); each process exits and the OS reclaims its memory
  #      before the next, so peak memory is bounded by a single member; then
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

    # +collection_config_path+ is the emitted collection manifest (the same
    # +collection-output.yaml+ the normal build renders). Member filerefs are
    # relative to its directory, so all per-member manifests are written there.
    def initialize(collection_config_path:, output_directory:, coverpage: nil,
                   store_dir: nil, formats: %i[xml html])
      @config_path = collection_config_path
      @config_dir = File.dirname(File.expand_path(collection_config_path))
      @output_directory = output_directory
      @coverpage = coverpage
      @store_dir = store_dir || File.join(output_directory, STORE_DIRNAME)
      @formats = formats
    end

    def build
      FileUtils.mkdir_p(@output_directory)
      FileUtils.mkdir_p(@store_dir)
      members = collection_members
      Utils.log "[staged] #{members.size} members; one process per member, " \
                "sequential; store: #{@store_dir}"
      members.each_with_index { |member, i| stage_member(member, i) }
      reinflate(members)
    end

    private

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
                compile: { install_fonts: false } },
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
                compile: { install_fonts: false } }.compact,
      )
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
