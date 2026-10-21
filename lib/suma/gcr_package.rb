# frozen_string_literal: true

require "yaml"
require "zip"
require "glossarist"
require "fileutils"

module Suma
  # Packages extracted Glossarist concepts into a GCR (Glossarist Concept
  # Repository) archive — the sealed distribution format consumed by the
  # Glossarist Vocabulary Browser (docs/gcr-spec.md in concept-browser).
  #
  # Standard variant only: metadata.yaml + register.yaml + concepts/ in the
  # browser's canonical flat format (termid, term, {lang} blocks). The -full
  # variant (SKOS/TBX/JSONL compilations) is out of scope.
  class GcrPackage
    SCHEMA_VERSION = "1.0.0"

    attr_reader :shortname, :version

    # @param concepts_dir [String] TermExtractor output directory
    # @param register_file [String] register.yaml (dataset identity)
    # @param shortname [String] dataset id (datasets.yml `id`)
    # @param version [String] semver of this dataset release
    # @param title [String] human-readable dataset title
    # @param description [String] dataset description
    # @param created_at [Time, nil] package timestamp; pinned packages pass
    #   a fixed time so the archive is byte-reproducible
    def initialize(concepts_dir:, register_file:, shortname:, version:,
                   title:, description:, created_at: nil)
      @concepts_dir = File.expand_path(concepts_dir)
      @register_file = File.expand_path(register_file)
      @shortname = shortname
      @version = version
      @title = title
      @description = description
      @created_at = created_at || Time.now
    end

    # Write the versioned and unversioned .gcr archives.
    #
    # @param output_dir [String]
    # @return [Array<String>] written archive paths
    def write(output_dir)
      FileUtils.mkdir_p(output_dir)
      entries = package_entries
      [versioned_name, unversioned_name].map do |name|
        path = File.join(output_dir, name)
        write_zip(path, entries)
        Utils.log "Wrote GCR package: #{path}"
        path
      end
    end

    # Canonical concept hashes, in deterministic (termid) order.
    #
    # @return [Array<Hash>]
    def canonical_concepts
      @canonical_concepts ||= concept_documents
        .map { |document| canonicalize(document) }
        .sort_by { |hash| hash["termid"] }
    end

    # @return [Hash] metadata.yaml content
    def metadata
      register = Glossarist::DatasetRegister.from_file(@register_file)
      {
        "shortname" => @shortname,
        "version" => @version,
        "title" => @title,
        "description" => @description,
        "glossarist_version" => Glossarist::VERSION,
        "created_at" => @created_at.utc.iso8601,
        "created_by" => "suma CLI",
        "uri" => register.urn,
        "uri_aliases" => register.urn_aliases,
        "statistics" => statistics,
        "schema_version" => SCHEMA_VERSION,
      }
    end

    def statistics
      languages = canonical_concepts
        .flat_map { |hash| hash.keys - %w[termid term] }
        .uniq.sort
      {
        "total_concepts" => canonical_concepts.length,
        "languages" => languages,
        "concepts_with_definitions" => concepts_with("definition"),
        "concepts_with_sources" => concepts_with("sources"),
        "concepts_by_status" => { "valid" => canonical_concepts.length },
      }
    end

    def concepts_with(key)
      canonical_concepts.count do |hash|
        hash.values.any? { |block| block.is_a?(Hash) && Array(block[key]).any? }
      end
    end

    private

    def concept_documents
      @concept_documents ||= Dir[File.join(@concepts_dir,
                                           "*.yaml")].map do |path|
        Glossarist::V3::ConceptDocument.from_yamls(File.read(path))
      end
    end

    # Convert a V3 ConceptDocument stream to the browser's canonical flat
    # concept hash (termid, term, one block per language).
    def canonicalize(document)
      concept = document.concept
      hash = { "termid" => concept.data.id }
      document.localizations.each do |localized|
        data = localized.data
        language = data.language_code
        hash[language] = language_block(data)
        hash["term"] ||= preferred_designation(data.terms)
      end
      validate_canonical!(hash)
      hash
    end

    def language_block(data)
      block = { "terms" => term_entries(data) }
      definitions = Array(data.definition)
      unless definitions.empty?
        block["definition"] =
          definition_entries(definitions)
      end
      notes = Array(data.notes).map do |note|
        note.respond_to?(:content) ? note.content : note.to_s
      end
      block["notes"] = notes unless notes.empty?
      sources = Array(data.sources).map { |source| source_hash(source) }
      block["sources"] = sources unless sources.empty?
      block["language_code"] = data.language_code
      block
    end

    def term_entries(data)
      Array(data.terms).map do |term|
        {
          "type" => term.type,
          "designation" => term.designation,
          "normative_status" => term.normative_status,
        }
      end
    end

    def definition_entries(definitions)
      definitions.map { |definition| { "content" => definition.content } }
    end

    def source_hash(source)
      ref = source.origin&.ref
      origin = {}
      if ref
        origin["ref"] =
          { "source" => ref.source, "version" => ref.version }.compact
      end
      { "type" => source.type, "origin" => origin }
    end

    def preferred_designation(terms)
      preferred = Array(terms).find do |term|
        term.normative_status == "preferred"
      end
      (preferred || Array(terms).first)&.designation
    end

    def validate_canonical!(hash)
      termid = hash["termid"]
      unless termid.is_a?(String) && !termid.empty?
        raise Error, "concept without termid"
      end

      return if language_blocks(hash).any? do |block|
        Array(block["terms"]).any?
      end

      raise Error, "concept #{termid} has no language block with a term"
    end

    def language_blocks(hash)
      hash.values.grep(Hash)
    end

    def package_entries
      entries = {
        "metadata.yaml" => "#{YAML.dump(metadata)}\n",
        "register.yaml" => File.read(@register_file),
      }
      seen = {}
      canonical_concepts.each do |hash|
        termid = hash["termid"]
        if seen[termid]
          raise Error, "duplicate termid in package: #{termid}"
        end

        seen[termid] = true
        entries["concepts/#{termid}.yaml"] = YAML.dump(hash)
      end
      entries
    end

    def versioned_name
      "#{@shortname}-#{@version}.gcr"
    end

    def unversioned_name
      "#{@shortname}.gcr"
    end

    def write_zip(path, entries)
      buffer = Zip::OutputStream.write_buffer do |stream|
        entries.each do |name, content|
          stream.put_next_entry(name)
          stream.write(content)
        end
      end
      File.binwrite(path, buffer.string)
    end
  end
end
