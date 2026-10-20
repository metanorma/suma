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
      option :profile, type: :string, default: "iso10303",
                       desc: "Corpus profile (iso10303 or generic)"
      option :edition, type: :numeric,
                       desc: "Owning edition recorded on each concept"
      option :language_codes, type: :array,
                              desc: "Additional linked localization " \
                                    "languages (the primary language is " \
                                    "always included)"

      def extract_terms(schema_manifest_file, output_path)
        TermExtractor.new(
          schema_manifest_file,
          output_path,
          language_code: options[:language_code],
          urn: options[:urn],
          profile: options[:profile],
          edition: options[:edition],
          language_codes: options[:language_codes],
        ).call
      end
    end
  end
end
