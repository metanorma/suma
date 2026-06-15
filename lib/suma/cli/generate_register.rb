# frozen_string_literal: true

require "thor"
require_relative "../thor_ext"
require_relative "../register_generator"

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

      def generate_register(schema_manifest_file, output_path)
        unless File.exist?(File.expand_path(schema_manifest_file))
          raise Errno::ENOENT, "Specified SCHEMA_MANIFEST_FILE " \
                               "`#{schema_manifest_file}` not found."
        end

        RegisterGenerator.new(
          schema_manifest_file,
          output_path,
          urn: options[:urn],
          id: options[:id],
          ref: options[:ref],
          language_code: options[:language_code],
        ).generate
      end
    end
  end
end
