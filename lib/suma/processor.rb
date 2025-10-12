# frozen_string_literal: true

require_relative "schema_collection"
require_relative "utils"
require_relative "collection_config"
require_relative "site_config"
require "metanorma/cli"
require "metanorma/cli/collection"
require "metanorma/collection/collection"

module Suma
  class Processor
    class << self
      # rubocop:disable Metrics/MethodLength
      def run(metanorma_yaml_path:, schemas_all_path:, compile:,
output_directory: "_site")
        Utils.log "Current directory: #{Dir.getwd}, writing #{schemas_all_path}..."

        # Generate EXPRESS Schema Manifest by traversing Metanorma Site Manifest
        # This uses Expressir::SchemaManifest for all manifest operations
        collection_config = export_schema_config(metanorma_yaml_path,
                                                 schemas_all_path)

        unless compile
          Utils.log "No compile option set. Skipping schema compilation."
          return nil
        end

        Utils.log "Compiling schema collection..."
        compile_schema(schemas_all_path, collection_config)

        Utils.log "Compiling complete collection..."
        compile_collection(collection_config, output_directory)
      end
      # rubocop:enable Metrics/MethodLength

      private

      # Generates EXPRESS Schema Manifest from Metanorma Site Manifest structure.
      #
      # This method:
      # 1. Reads the Metanorma site manifest to discover collection files
      # 2. Traverses collection manifests to find individual schemas.yaml files
      # 3. Uses Expressir::SchemaManifest to aggregate and manage schema entries
      # 4. Saves the unified schema manifest using Expressir's to_file method
      #
      # @param metanorma_yaml_path [String] Path to Metanorma site manifest
      # @param schemas_all_path [String] Output path for unified schema manifest
      # @return [CollectionConfig] The loaded collection configuration
      # rubocop:disable Metrics/MethodLength
      def export_schema_config(metanorma_yaml_path, schemas_all_path)
        # This reads the metanorma.yml file
        site_config = Suma::SiteConfig::Config.from_file(metanorma_yaml_path)

        # TODO: only reading the first file, which is a collection.yml, which is a hack...
        collection_config_path = site_config.metanorma.source.files.first
        collection_config = Suma::CollectionConfig.from_file(collection_config_path)
        collection_config.path = collection_config_path
        collection_config.manifest.expand_schemas_only("schema_docs")

        # Recursively traverse collection manifests to build unified schema manifest
        # Uses Expressir::SchemaManifest methods (concat, to_file) for operations
        exported_schema_config = collection_config.manifest.export_schema_config(schemas_all_path)
        exported_schema_config.path = schemas_all_path

        # Save using Expressir's SchemaManifest#to_file method
        exported_schema_config.to_file

        collection_config
      end
      # rubocop:enable Metrics/MethodLength

      def compile_schema(schemas_all_path, collection_config)
        # now get rid of the source documents for schema sources
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

        # TODO: Temporarily disable removal of XML files
        Dir.glob(File.join(Dir.getwd, output_directory,
                           "*.xml")).each do |file|
          puts "NOT DELETING ANY FILE #{file.inspect}"
          # File.delete(file)
        end
      end

      def build_collection(collection_config, output_directory)
        new_collection_config_path = "collection-output.yaml"
        collection_config.manifest.remove_schemas_only_sources
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
end
