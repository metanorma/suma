# frozen_string_literal: true

require "digest"
require "uuidtools"

module Suma
  # Removes Metanorma's nondeterminism from collection output.
  #
  # Metanorma assigns a random UUID to every collection manifest node that
  # lacks an identifier (Manifest#identifier's default) and stamps each
  # rendered document with a random 8-letter type marker
  # (collection/xrefprocess). Both leak into the emitted manifest and the XML
  # output, so two identical builds produce different bytes.
  #
  # Manifest identifiers are replaced IN THE MODEL before serialization:
  # Psych's quoting of the resulting strings is value-dependent (a few
  # percent of UUID-looking values get single-quoted), so patching the dumped
  # YAML afterwards would preserve a random quoting decision. Values that
  # appear in the source YAML are preserved.
  class OutputCanonicalizer
    UUID_PATTERN =
      /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/
    FULL_UUID_PATTERN = /\A#{UUID_PATTERN.source}\z/
    CANONICAL_TYPE = "SUMASUMA"
    NAMESPACE = UUIDTools::UUID.parse("6ba7b810-9dad-11d1-80b4-00c04fd430c8")

    def initialize(output_directory:, sources: [])
      @output_directory = File.expand_path(output_directory)
      @sources = sources.map { |path| File.expand_path(path) }
    end

    # Replace generated manifest identifiers with deterministic UUIDv5s.
    # Must run before the manifest is serialized and the site key computed.
    def canonicalize_manifest(manifest)
      canonicalize_node(manifest, "collection-manifest")
      self
    end

    # Canonicalize the rendered site's root XML documents.
    def canonicalize_documents
      Dir.glob(File.join(@output_directory, "*.xml")).each do |file|
        canonicalize_document(file)
      end
      self
    end

    private

    def canonicalize_node(node, seed)
      return unless node

      if generated_uuid?(node.identifier)
        node.identifier = uuid_v5("suma-manifest:#{seed}").to_s
      end
      Array(node.entry).each_with_index do |child, index|
        canonicalize_node(child, "#{seed}/#{index}")
      end
    end

    def generated_uuid?(value)
      value.to_s.match?(FULL_UUID_PATTERN) && !preserved.include?(value)
    end

    def canonicalize_document(file)
      content = File.read(file)
      canonical = replace_uuids(content, File.basename(file))
      canonical = replace_type(canonical)
      File.write(file, canonical) if canonical != content
    end

    def replace_uuids(content, seed)
      index = 0
      content.gsub(UUID_PATTERN) do |uuid|
        next uuid if preserved.include?(uuid)

        index += 1
        uuid_v5("suma-document:#{seed}:#{index}").to_s
      end
    end

    def replace_type(content)
      content.sub(/(<metanorma\b[^>]*\btype=")[A-Z]{8}(")/) do
        "#{Regexp.last_match(1)}#{CANONICAL_TYPE}#{Regexp.last_match(2)}"
      end
    end

    # UUIDs that occur in the site's source YAML. Identifiers the author
    # wrote must survive; only generated ones are replaced. YAML is read as
    # bytes: an author-supplied file with non-UTF-8 bytes must not fail the
    # build, and the pattern is ASCII-only.
    def preserved
      @preserved ||= yaml_sources.flat_map do |file|
        File.binread(file).scan(UUID_PATTERN)
      end.uniq
    end

    def yaml_sources
      @sources.select do |file|
        file.match?(/\.ya?ml\z/i) && File.file?(file)
      end
    end

    def uuid_v5(name)
      UUIDTools::UUID.sha1_create(NAMESPACE, name)
    end
  end
end
