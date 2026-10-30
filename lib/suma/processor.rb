# frozen_string_literal: true

require "metanorma"
require "expressir"

module Suma
  class Processor
    # Emitted collection manifest that both the normal and staged builds render.
    COLLECTION_OUTPUT_PATH = "collection-output.yaml"

    attr_reader :metanorma_yaml_path, :output_directory, :schemas_all_path,
                :compile_flag

    def initialize(metanorma_yaml_path:, schemas_all_path:, compile: true,
                   output_directory: "_site", staged: false,
                   staged_workers: 1, staged_batch_size: nil,
                   incremental: false, state_file: nil, jobs: 1,
                   provenance_file: nil, sign_method: nil, sign_key: nil,
                   no_valid: false)
      @metanorma_yaml_path = metanorma_yaml_path
      @schemas_all_path = schemas_all_path
      @compile_flag = compile
      @output_directory = output_directory
      # Opt-in memory-bounded staged build (metanorma/suma#94); the default
      # single-process build below is unchanged when false.
      @staged = staged
      @staged_workers = staged_workers
      @staged_batch_size = staged_batch_size
      @incremental = incremental
      @state_file = state_file
      @jobs = jobs
      @provenance_file = provenance_file
      @sign_method = sign_method
      @sign_key = sign_key
      # Skip Metanorma document validation (metanorma `--no-valid`). Opt-in:
      # for collections whose flavor's validators are still in flight.
      @no_valid = no_valid
    end

    def run
      Utils.log "Current directory: #{Dir.getwd}, writing #{schemas_all_path}..."

      collection_config = export_schema_config

      if @compile_flag
        Utils.log "Compiling schema collection..."
        compile_schema(schemas_all_path, collection_config)

        compile_collection(collection_config, output_directory)
      end

      write_provenance
      nil
    end

    private

    def write_provenance
      return unless @provenance_file

      Provenance.write(
        @provenance_file,
        inputs: provenance_inputs,
        outputs: provenance_outputs,
        exclude: provenance_excludes,
      )
      if @sign_method
        signature = Provenance.sign(
          @provenance_file, method: @sign_method, key: @sign_key
        )
        Utils.log "Signed build provenance (#{@sign_method}): #{signature}"
      end
      Utils.log "Wrote build provenance: #{@provenance_file}"
    end

    def provenance_inputs
      [@metanorma_yaml_path, @schemas_all_path] + schema_source_paths
    end

    def schema_source_paths
      manifest = Expressir::SchemaManifest.from_file(@schemas_all_path)
      manifest.schemas.map { |entry| entry.path.to_s }
    end

    def provenance_outputs
      [COLLECTION_OUTPUT_PATH, "plain_schemas", "schema_docs",
       @output_directory]
    end

    # Build metadata that is not site content: the site freshness state, the
    # staged-build store, and a provenance file written inside the output tree.
    def provenance_excludes
      excludes = [File.join(@output_directory, SiteBuild::STATE_FILE)]
      if @staged
        excludes << File.join(@output_directory,
                              StagedCollectionBuilder::STORE_DIRNAME)
        excludes << File.join(@output_directory, "_staged_reinflate")
      end
      excludes + provenance_artifacts.select { |path| within_output?(path) }
    end

    def provenance_artifacts
      return [] unless @provenance_file

      base = File.expand_path(@provenance_file)
      [base, "#{base}.minisig", "#{base}.bundle"]
    end

    def within_output?(path)
      full = File.expand_path(path)
      output = File.expand_path(@output_directory)
      full == output || full.start_with?("#{output}#{File::SEPARATOR}")
    end

    def export_schema_config
      site_config = Suma::SiteConfig::Config.from_file(metanorma_yaml_path)

      collection_config_path = site_config.metanorma.source.files.first
      collection_config = Suma::CollectionConfig.from_file(collection_config_path)
      collection_config.path = collection_config_path

      traverser = ManifestTraverser.new(collection_config.manifest)
      traverser.expand_schemas_only("schema_docs")

      exported_schema_config = traverser.export_schema_config(schemas_all_path)
      exported_schema_config.path = schemas_all_path
      exported_schema_config.to_file

      collection_config
    end

    def compile_schema(schemas_all_path, collection_config)
      col = Suma::SchemaCollection.new(
        config_yaml: schemas_all_path,
        manifest: collection_config.manifest,
        output_path_docs: "schema_docs",
        output_path_schemas: "plain_schemas",
        options: {
          annotations: true,
          incremental: @incremental,
          state_file: @state_file,
          jobs: @jobs,
          no_valid: @no_valid,
        },
      )

      col.compile
    end

    def compile_collection(collection_config, output_directory)
      prepare_collection_manifest(collection_config)
      write_collection_manifest(collection_config)

      if site_build.current?
        Utils.log "Collection outputs are up to date; 0 documents rendered."
        return
      end

      Utils.log "Rendering collection site..."
      render_collection(collection_config, output_directory)
      canonicalizer.canonicalize_documents
      site_build.record
    end

    # Generated manifest identifiers are canonicalized in the model, before
    # serialization: patching the dumped YAML would preserve Psych's
    # value-dependent (random) quoting decision.
    def prepare_collection_manifest(collection_config)
      ManifestTraverser.new(collection_config.manifest)
        .remove_schemas_only_sources
      canonicalizer.canonicalize_manifest(collection_config.manifest)
    end

    def write_collection_manifest(collection_config)
      collection_config.to_file(COLLECTION_OUTPUT_PATH)
    end

    def render_collection(collection_config, output_directory)
      if @staged
        # The emitted manifest is the staging input; each member is compiled
        # in its own process and then reinflated into +output_directory+.
        StagedCollectionBuilder.new(
          collection_config_path: COLLECTION_OUTPUT_PATH,
          output_directory: output_directory,
          coverpage: collection_coverpage(collection_config),
          no_valid: @no_valid,
          workers: @staged_workers,
          batch_size: @staged_batch_size ||
            StagedCollectionBuilder::DEFAULT_BATCH_SIZE,
        ).build
      else
        Metanorma::Collection.parse(COLLECTION_OUTPUT_PATH)
          .render(collection_options(collection_config, output_directory))
      end
    end

    def collection_options(collection_config, output_directory)
      {
        output_folder: output_directory,
        compile: compile_flags,
        coverpage: collection_coverpage(collection_config),
      }
    end

    def compile_flags
      { install_fonts: false }.tap do |flags|
        flags[:novalid] = true if @no_valid
      end
    end

    def collection_coverpage(collection_config)
      collection_config.coverpage || "cover.html"
    end

    def site_build
      @site_build ||= SiteBuild.new(
        root: File.dirname(File.expand_path(metanorma_yaml_path)),
        output_directory: output_directory,
        inputs: [schemas_all_path],
      )
    end

    def canonicalizer
      @canonicalizer ||= OutputCanonicalizer.new(
        output_directory: output_directory,
        sources: site_build.source_files,
      )
    end
  end
end
