# frozen_string_literal: true

require_relative "schema_config"
require_relative "schema_collection"
require_relative "utils"
require_relative "to_replace/collection_config"
require_relative "to_replace/site_config"
require "metanorma/cli"
require "metanorma/cli/collection"
require "metanorma/collection/collection"

module Suma
  class Processor
    class << self
      # Can move to schema_config.rb
      def write_all_schemas(schemas_all_path, document_paths)
        all_schemas = Suma::SchemaConfig::Config.new(path: schemas_all_path)

        document_paths.each do |path|
          schemas_yaml = File.join(File.dirname(path), "schemas.yaml")
          next unless File.exist?(schemas_yaml)

          schemas_config = Suma::SchemaConfig::Config.from_file(schemas_yaml)
          all_schemas.concat(schemas_config)
        end

        Utils.log "Writing #{schemas_all_path}..."
        all_schemas.to_file
        Utils.log "Done."
      end

      def run(metanorma_yaml_path:, schemas_all_path:, compile:, output_directory: "_site")
        Utils.log "Current directory: #{Dir.getwd}"

        # This reads the metanorma.yml file
        site_config = Suma::ToReplace::SiteConfig::Config.from_file(metanorma_yaml_path)

        # TODO: only reading the first file, which is a collection.yml, which is a hack...
        collection_config_path = site_config.metanorma.source.files.first
        collection_config = Suma::ToReplace::CollectionConfig::Config.from_file(collection_config_path)
        collection_config.path = collection_config_path

        # Gather all the inner (per-document) collection.yml files
        document_paths = collection_config.manifest.docref.map(&:file)

        write_all_schemas(schemas_all_path, document_paths)

        col = Suma::SchemaCollection.new(
          config_yaml: schemas_all_path,
          output_path_docs: "schema_docs",
          output_path_schemas: "plain_schemas"
        )

        if compile
          Utils.log "Compiling schema collection..."
          col.compile
        else
          Utils.log "No compile option set. Skipping schema compilation."
        end

        # TODO: Do we still need this?
        # Define Proc to resolve fileref
        my_fileref_proc = proc do |ref_folder, fileref|
          # move schemas to modified_schemas
          if File.extname(fileref) == ".exp"
            fileref.gsub!(
              "../../schemas",
              "modified_schemas"
            )
          end
          File.join(ref_folder, fileref)
        end

        # TODO: Do we still need this?
        # Define Proc to resolve identifier
        my_identifier_proc = proc do |identifier|
          case identifier
          when %r{^documents/}
            identifier.gsub("documents/", "")
          else
            identifier
          end
        end

        # TODO: Do we still need this?
        # Define Proc to handle the compilation of express schemas
        express_schemas_renderer = proc do |collection_model|
        end

        # TODO: Do we still need this?
        Metanorma::Collection.tap do |mn|
          mn.set_identifier_resolver(&my_identifier_proc)
          mn.set_fileref_resolver(&my_fileref_proc)
          mn.set_pre_parse_model(&express_schemas_renderer)
        end

        if compile
          Utils.log "Compiling complete collection..."

          metanorma_collection = Metanorma::Collection.parse(collection_config_path)

          # TODO: Somehow this is no longer used
          collection_opts = {
            format: [:html],
            output_folder: output_directory,
            compile: {
              no_install_fonts: true
            },
            coverpage: "cover.html"
          }
          metanorma_collection.render(collection_opts)

          # remove xml files
          Dir.glob(File.join(Dir.getwd, output_directory, "*.xml")).each do |file|
            File.delete(file)
          end
        else
          Utils.log "No compile option set. Skipping collection compilation."
        end
      end
    end
  end
end
