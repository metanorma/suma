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
                   incremental: false, state_file: nil, jobs: 1,
                   provenance_file: nil, sign_method: nil, sign_key: nil)
      @metanorma_yaml_path = metanorma_yaml_path
      @schemas_all_path = schemas_all_path
      @compile_flag = compile
      @output_directory = output_directory
      # Opt-in memory-bounded staged build (metanorma/suma#94); the default
      # single-process build below is unchanged when false.
      @staged = staged
      @incremental = incremental
      @state_file = state_file
      @jobs = jobs
      @provenance_file = provenance_file
      @sign_method = sign_method
      @sign_key = sign_key
    end

    def run
      Utils.log "Current directory: #{Dir.getwd}, writing #{schemas_all_path}..."

      collection_config = export_schema_config

      if @compile_flag
        Utils.log "Compiling schema collection..."
        compile_schema(schemas_all_path, collection_config)

        Utils.log "Compiling complete collection..."
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
        },
      )

      col.compile
    end

    def compile_collection(collection_config, output_directory)
      metanorma_collection, collection_opts = build_collection(
        collection_config, output_directory
      )

      if @staged
        # build_collection has written the emitted manifest; stage each member in
        # its own process, then reinflate. Bounds peak memory to a single member.
        StagedCollectionBuilder.new(
          collection_config_path: COLLECTION_OUTPUT_PATH,
          output_directory: output_directory,
          coverpage: collection_opts[:coverpage],
        ).build
      else
        metanorma_collection.render(collection_opts)
      end
    end

    def build_collection(collection_config, output_directory)
      new_collection_config_path = COLLECTION_OUTPUT_PATH
      ManifestTraverser.new(collection_config.manifest).remove_schemas_only_sources
      collection_config.to_file(new_collection_config_path)

      collection = Metanorma::Collection.parse(new_collection_config_path)

      collection_opts = {
        output_folder: output_directory,
        compile: { install_fonts: false },
        coverpage: collection_config.coverpage || "cover.html",
      }
      [collection, collection_opts]
    end
  end
end
