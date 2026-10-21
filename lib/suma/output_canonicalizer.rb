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
  # output, so two identical builds produce different bytes. This pass
  # replaces those values with position-derived (UUIDs) or fixed (type)
  # values, while leaving identifiers that appear in the source untouched.
  class OutputCanonicalizer
    UUID_PATTERN =
      /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/
    CANONICAL_TYPE = "SUMASUMA"
    NAMESPACE = UUIDTools::UUID.parse("6ba7b810-9dad-11d1-80b4-00c04fd430c8")

    def initialize(output_directory:, manifest_path: nil, sources: [])
      @output_directory = File.expand_path(output_directory)
      @manifest_path = manifest_path && File.expand_path(manifest_path)
      @sources = sources.map { |path| File.expand_path(path) }
    end

    def call
      canonicalize_manifest
      canonicalize_documents
      self
    end

    # Canonicalize the emitted collection manifest. Must run before the site
    # key is computed, so the key does not change on every build.
    def canonicalize_manifest
      return unless @manifest_path && File.file?(@manifest_path)

      canonicalize_file(@manifest_path, path: "collection-output.yaml")
    end

    # Canonicalize the rendered site's root XML documents.
    def canonicalize_documents
      Dir.glob(File.join(@output_directory, "*.xml")).each do |file|
        canonicalize_file(file, path: File.basename(file), documents: true)
      end
    end

    private

    def canonicalize_file(file, path:, documents: false)
      content = File.read(file)
      canonical = replace_uuids(content, path)
      canonical = replace_type(canonical) if documents
      File.write(file, canonical) if canonical != content
    end

    def replace_uuids(content, seed)
      index = 0
      content.gsub(UUID_PATTERN) do |uuid|
        next uuid if preserved.include?(uuid)

        index += 1
        uuid_v5("#{seed}:#{index}").to_s
      end
    end

    def replace_type(content)
      content.sub(/(<metanorma\b[^>]*\btype=")[A-Z]{8}(")/) do
        "#{Regexp.last_match(1)}#{CANONICAL_TYPE}#{Regexp.last_match(2)}"
      end
    end

    # UUIDs that occur in the site's source YAML. Identifiers the author
    # wrote must survive; only generated ones are replaced.
    def preserved
      @preserved ||= yaml_sources.flat_map do |file|
        File.read(file).scan(UUID_PATTERN)
      end.uniq
    end

    def yaml_sources
      @sources.select do |file|
        file != @manifest_path && file.match?(/\.ya?ml\z/i) && File.file?(file)
      end
    end

    def uuid_v5(name)
      UUIDTools::UUID.sha1_create(NAMESPACE, name)
    end
  end
end
