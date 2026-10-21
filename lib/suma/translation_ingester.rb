# frozen_string_literal: true

require "fileutils"
require "glossarist"
require "yaml"

module Suma
  # Overlays translated content onto extracted Glossarist concepts (T5).
  #
  # A translations file is a YAML sequence of localized-concept documents,
  # each carrying an identity key plus the content to apply:
  #
  #   - concept_id: example_schema.bolt   # managed id (data.identifier)
  #                                       # or the managed concept's uuid
  #   - id: <localized uuid>              # alternative identity key
  #     data:
  #       language_code: fra
  #       terms: [...]
  #       definition: [...]
  #
  # Every field the entry provides replaces the localization's field; every
  # field it omits falls back, explicitly, to the localization's current
  # content (for a new language: the source-language localization's). All
  # (de)serialization goes through the Glossarist/lutaml-model framework;
  # entries are merged as serialized hashes and reified with of_yaml.
  class TranslationIngester
    def initialize(concepts_dir:, translations:, output_dir: nil)
      @concepts_dir = concepts_dir
      @translations = translations
      @output_dir = output_dir || concepts_dir
    end

    # @return [Hash{String=>Array<String>}] concept file → applied entry
    #   identities
    def ingest
      entries = load_entries
      applied = {}
      each_concept_document do |file, doc|
        matched = entries_for(doc, entries)
        next if matched.empty?

        applied[file] = matched.map { |entry| apply_entry(doc, entry) }
        write_document(file, doc)
      end
      assert_no_unmatched!(entries, applied)
      applied
    end

    private

    def load_entries
      content = YAML.safe_load_file(@translations, permitted_classes: [],
                                                   aliases: true)
      entries = content.is_a?(Hash) ? content["translations"] : content
      unless entries.is_a?(Array)
        raise Error,
              "translations file must be a YAML sequence of localized " \
              "concepts: #{@translations}"
      end

      entries
    end

    def each_concept_document
      Dir.glob(File.join(@concepts_dir, "*.yaml")).each do |file|
        doc = Glossarist::V3::ConceptDocument.from_yamls(File.read(file))
        yield file, doc
      end
    end

    def entries_for(doc, entries)
      entries.select { |entry| entry_matches?(doc, entry) }
    end

    def entry_matches?(doc, entry)
      if entry["concept_id"]
        [doc.concept.data.id, doc.concept.uuid].include?(entry["concept_id"])
      else
        localized_uuids(doc).include?(entry["id"])
      end
    end

    def localized_uuids(doc)
      doc.localizations.map(&:id) +
        doc.concept.data.localized_concepts.values
    end

    def apply_entry(doc, entry)
      incoming = Glossarist::LocalizedConcept
        .of_yaml(entry.except("concept_id"))
      localized = merge_localization(doc, entry, incoming)
      replace_localization(doc, localized)
      entry["concept_id"] || entry["id"]
    end

    def replace_localization(doc, localized)
      language = localized.data.language_code
      doc.localizations.reject! { |l10n| l10n.data.language_code == language }
      doc.localizations << localized
      doc.concept.data.localized_concepts[language] = localized.uuid
    end

    # Entry fields win; absent fields keep the localization's current
    # content (or the source-language content for a new language). The
    # merge happens on the raw entry data — a parsed model would
    # materialize empty collections and wipe the fields it omits.
    #
    # Glossarist parses the serialized "id" key into `#id` (not `#uuid`),
    # so the persisted id is preserved and stamped back onto the merged
    # localization explicitly; a new language gets the same v5 id
    # TermExtractor's linked localizations use.
    def merge_localization(doc, entry, incoming)
      current = current_localization(doc, entry, incoming)
      base = current || doc.localizations.first
      return incoming unless base

      identity = entry["id"] || current&.id ||
        new_localization_uuid(doc, incoming.data.language_code)
      localized = Glossarist::LocalizedConcept
        .of_yaml(merged_hash(base, entry, identity))
      localized.uuid = identity
      localized
    end

    def merged_hash(base, entry, identity)
      merged = base.to_yaml_hash
      merged["data"] = (merged["data"] || {})
        .merge(entry["data"] || {})
      merged["id"] = identity
      merged
    end

    def current_localization(doc, entry, incoming)
      if entry["id"]
        doc.localizations.find { |l10n| l10n.id == entry["id"] }
      else
        doc.localizations.find do |l10n|
          l10n.data.language_code == incoming.data.language_code
        end
      end
    end

    # Same convention as TermExtractor's linked localizations.
    def new_localization_uuid(doc, language)
      Glossarist::Utilities::UUID.uuid_v5(
        Glossarist::Utilities::UUID::OID_NAMESPACE,
        "#{doc.concept.data.id}-#{language}",
      )
    end

    def write_document(file, doc)
      output = File.join(@output_dir, File.basename(file))
      FileUtils.mkdir_p(@output_dir) if output != file
      File.write(output, doc.to_yamls, encoding: "utf-8")
    end

    def assert_no_unmatched!(entries, applied)
      matched = applied.values.flatten
      unmatched = entries.reject do |entry|
        matched.include?(entry["concept_id"] || entry["id"])
      end
      return if unmatched.empty?

      raise Error,
            "unmatched translation entries: " \
            "#{unmatched.map { |e| e['concept_id'] || e['id'] }.join(', ')}"
    end
  end
end
