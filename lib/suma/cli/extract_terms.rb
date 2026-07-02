# frozen_string_literal: true

require "thor"

module Suma
  module Cli
    class ExtractTerms < Thor
      desc "extract_terms SCHEMA_MANIFEST_FILE GLOSSARIST_OUTPUT_PATH",
           "Extract terms from SCHEMA_MANIFEST_FILE into " \
           "Glossarist v3 format"
      option :language_code, type: :string, default: "eng", aliases: "-l",
                             desc: "Language code for the Glossarist"
      option :urn, type: :string, required: true, aliases: "-u",
                   desc: "URN for the dataset source " \
                         "(used for section references)"

      def extract_terms(schema_manifest_file, output_path)
        TermExtractor.new(
          schema_manifest_file,
          output_path,
          language_code: options[:language_code],
          urn: options[:urn],
        ).call
      end
    end
  end
end
