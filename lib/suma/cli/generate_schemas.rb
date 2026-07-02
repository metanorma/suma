# frozen_string_literal: true

require "thor"

module Suma
  module Cli
    class GenerateSchemas < Thor
      desc "generate_schemas METANORMA_MANIFEST_FILE SCHEMA_MANIFEST_FILE",
           "Generate EXPRESS schema manifest file from Metanorma site manifest"
      option :exclude_paths, type: :string, default: nil, aliases: "-e",
                             desc: "Exclude schemas paths by pattern " \
                                   "(e.g. `*_lf.exp`)"

      def generate_schemas(metanorma_manifest_file, schema_manifest_file)
        SchemaManifestGenerator.new(
          metanorma_manifest_file,
          schema_manifest_file,
          exclude_paths: options[:exclude_paths],
        ).generate
      end
    end
  end
end
