# frozen_string_literal: true

require "thor"

module Suma
  module Cli
    # Ingest translated localized-concept content into extracted concepts.
    class IngestTranslations < Thor
      def self.exit_on_failure?
        true
      end

      desc "ingest_translations CONCEPTS_DIR TRANSLATIONS_FILE",
           "Overlay translated localized-concept content onto extracted " \
           "Glossarist concepts; fields the translations omit fall back " \
           "to the source-language content"
      option :output, type: :string, aliases: "-o",
                      desc: "Write updated concepts here (default: " \
                            "update CONCEPTS_DIR in place)"

      def ingest_translations(concepts_dir, translations_file)
        unless File.file?(translations_file)
          raise Errno::ENOENT, translations_file
        end

        applied = TranslationIngester.new(
          concepts_dir: concepts_dir,
          translations: translations_file,
          output_dir: options[:output],
        ).ingest
        Utils.log "Applied #{applied.values.sum(&:size)} translation(s) " \
                  "to #{applied.size} concept(s)."
      end
    end
  end
end
