# frozen_string_literal: true

require "metanorma"

module Suma
  class Processor
    attr_reader :metanorma_yaml_path, :output_directory, :schemas_all_path,
                :compile_flag

    def initialize(metanorma_yaml_path:, schemas_all_path:, compile: true,
                   output_directory: "_site")
      @metanorma_yaml_path = metanorma_yaml_path
      @schemas_all_path = schemas_all_path
      @compile_flag = compile
      @output_directory = output_directory
    end

    def run
      Utils.log "Current directory: #{Dir.getwd}, writing #{schemas_all_path}..."

      collection_config = export_schema_config

      return nil unless @compile_flag

      Utils.log "Compiling schema collection..."
      compile_schema(schemas_all_path, collection_config)

      Utils.log "Compiling complete collection..."
      compile_collection(collection_config, output_directory)
    end

    private

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
      )

      col.compile
    end

    def compile_collection(collection_config, output_directory)
      metanorma_collection, collection_opts = build_collection(
        collection_config, output_directory
      )

      metanorma_collection.render(collection_opts)
    end

    def build_collection(collection_config, output_directory)
      new_collection_config_path = "collection-output.yaml"
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
