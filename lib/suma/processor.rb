# frozen_string_literal: true

require_relative "schema_config"
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

      def run(metanorma_yaml_path:, schemas_all_path:, compile:, output_directory: "_site")
        Utils.log "Current directory: #{Dir.getwd}"

        # This reads the metanorma.yml file
        site_config = Suma::SiteConfig::Config.from_file(metanorma_yaml_path)

        # TODO: only reading the first file, which is a collection.yml, which is a hack...
        collection_config_path = site_config.metanorma.source.files.first
        collection_config = Suma::CollectionConfig.from_file(collection_config_path)
        collection_config.path = collection_config_path
        collection_config.manifest.expand_schemas_only("schema_docs")

        exported_schema_config = collection_config.manifest.export_schema_config(schemas_all_path)
        exported_schema_config.path = schemas_all_path

        Utils.log "Writing #{schemas_all_path}..."
        exported_schema_config.to_file
        Utils.log "Done."

        # now get rid of the source documents for schema sources

        col = Suma::SchemaCollection.new(
          config_yaml: schemas_all_path,
          manifest: collection_config.manifest,
          output_path_docs: "schema_docs",
          output_path_schemas: "plain_schemas",
        )

        if compile
          Utils.log "Compiling schema collection..."
          col.compile
        else
          Utils.log "No compile option set. Skipping schema compilation."
        end

        new_collection_config_path = "collection-output.yaml"
        collection_config.manifest.remove_schemas_only_sources
        collection_config.to_file(new_collection_config_path)

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

          # TODO: Why will defining a collection immediately compile??
          metanorma_collection = Metanorma::Collection.parse(new_collection_config_path)

          # TODO: Somehow this is no longer used
          collection_opts = {
            format: [:html],
            output_folder: output_directory,
            compile: {
              no_install_fonts: true,
            },
            coverpage: "cover.html",
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
