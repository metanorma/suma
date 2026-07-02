# frozen_string_literal: true

require "thor"

module Suma
  module Cli
    class GenerateRegister < Thor
      desc "generate_register SCHEMA_MANIFEST_FILE OUTPUT_PATH",
           "Generate a Glossarist register.yaml with hierarchical sections"
      option :language_code, type: :string, default: "eng", aliases: "-l",
                             desc: "Language code for section names"
      option :urn, type: :string, required: true, aliases: "-u",
                   desc: "URN prefix for the dataset"
      option :id, type: :string, required: true,
                  desc: "Dataset identifier (e.g. iso10303-2-express)"
      option :ref, type: :string, required: true,
                   desc: "Human-readable reference label"
      option :owner, type: :string, default: Suma::RegisterManifestGenerator::DEFAULT_OWNER,
                     desc: "Owner of the dataset (e.g. 'ISO/TC 184/SC 4')"

      def generate_register(schema_manifest_file, output_path)
        RegisterManifestGenerator.new(
          schema_manifest_file,
          output_path,
          urn: options[:urn],
          id: options[:id],
          ref: options[:ref],
          language_code: options[:language_code],
          owner: options[:owner],
        ).generate
      end
    end
  end
end
