# frozen_string_literal: true

require "expressir"
require "pathname"

module Suma
  # Change-impact analysis (S3): given a changed schema, which schemas and
  # AP publications are affected?
  #
  # Walks the reverse interface closure of the CorpusGraph, so the answer
  # is transitive: every schema that USEs FROM the changed schema directly
  # or through other schemas is reported, and every AP publication whose
  # dependency closure contains the changed schema is flagged.
  class ChangeImpact
    attr_reader :graph, :schema_manifest_file

    # @param graph [CorpusGraph]
    # @param schema_manifest_file [String] corpus manifest, for AP detection
    def initialize(graph, schema_manifest_file)
      @graph = graph
      @schema_manifest_file = schema_manifest_file
    end

    # @param schema_id [String] the changed schema
    # @return [Array<String>] transitively affected schema ids
    def affected_schemas(schema_id)
      graph.dependents_of(schema_id)
    end

    # @param schema_id [String] the changed schema
    # @return [Array<String>] AP publication leads whose closure includes it
    def affected_publications(schema_id)
      target = schema_id.to_s.downcase
      application_protocol_ids.select do |lead|
        graph.dependency_closure(lead).include?(target)
      end.sort
    end

    # @param schema_id [String]
    # @return [Hash]
    def report(schema_id)
      {
        "schema" => schema_id,
        "affected_schemas" => affected_schemas(schema_id),
        "affected_publications" => affected_publications(schema_id),
      }
    end

    private

    def application_protocol_ids
      manifest = Expressir::SchemaManifest.from_file(
        File.expand_path(schema_manifest_file),
      )
      manifest.schemas.select do |entry|
        SchemaCategory.for_schema(id: entry.id, path: entry.path) ==
          SchemaCategory::APPLICATION_PROTOCOLS
      end.map { |entry| entry.id.downcase }
    end
  end
end
