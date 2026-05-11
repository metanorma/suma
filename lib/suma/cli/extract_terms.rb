# frozen_string_literal: true

require "thor"
require_relative "../thor_ext"
require_relative "../term_extractor"

module Suma
  module Cli
    class ExtractTerms < Thor
      desc "extract_terms SCHEMA_MANIFEST_FILE GLOSSARIST_OUTPUT_PATH",
           "Extract terms from SCHEMA_MANIFEST_FILE into " \
           "Glossarist v2 format"
      option :language_code, type: :string, default: "eng", aliases: "-l",
                             desc: "Language code for the Glossarist"

      def extract_terms(schema_manifest_file, output_path)
        unless File.exist?(File.expand_path(schema_manifest_file))
          raise Errno::ENOENT, "Specified SCHEMA_MANIFEST_FILE " \
                               "`#{schema_manifest_file}` not found."
        end

        TermExtractor.new(
          schema_manifest_file,
          output_path,
          language_code: options[:language_code],
        ).call
      end
    end
  end
end
