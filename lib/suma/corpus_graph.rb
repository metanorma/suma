# frozen_string_literal: true

require "expressir"
# Expressir::SchemaManifest references Pathname without requiring it
# (expressir upstream gap); load it before any manifest parsing.
require "pathname"

module Suma
  # The declared-element graph of a schema collection: which schemas exist,
  # which elements each declares, and which schemas interface to which.
  #
  # This is the resolution substrate for S1 referential closure and, later,
  # change-impact analysis (S3) and dependency-driven builds (S6). Nodes are
  # schemas and their declared elements; edges are USE/REFERENCE interfaces.
  class CorpusGraph
    attr_reader :schema_ids

    def initialize(repositories)
      @schemas = {}
      @elements = {}
      @interfaces = {}

      repositories.each do |repo|
        repo.schemas.each { |schema| add_schema(schema) }
      end
      @schema_ids = @schemas.keys
      freeze
    end

    # Parse every schema in a manifest and build the graph.
    #
    # @param manifest_file [String] path to the schema manifest
    # @return [CorpusGraph]
    def self.from_manifest(manifest_file)
      manifest = Expressir::SchemaManifest.from_file(
        File.expand_path(manifest_file),
      )
      repositories = manifest.schemas.map do |entry|
        Expressir::Express::Parser.from_file(entry.path.to_s)
      end
      new(repositories)
    end

    # @param id [String]
    # @return [Boolean]
    def schema_exists?(id)
      @schemas.key?(normalize(id))
    end

    # Does +schema_id+ (or a schema it interfaces to) declare +element_id+?
    # EXPRESS resolves unqualified names against the local schema and
    # implicitly-used schemas.
    #
    # @param schema_id [String]
    # @param element_id [String]
    # @return [Boolean]
    def element_visible?(schema_id, element_id)
      key = normalize(schema_id)
      return false unless @elements.key?(key)

      return true if @elements[key].key?(normalize(element_id))

      visible_from_interfaces(key).include?(normalize(element_id))
    end

    # Schemas that +schema_id+ USEs FROM or REFERENCEs.
    #
    # @param schema_id [String]
    # @return [Array<String>] normalized ids of interface targets
    def interface_targets(schema_id)
      @interfaces[normalize(schema_id)] || []
    end

    private

    def add_schema(schema)
      key = normalize(schema.id)
      @schemas[key] = true
      @elements[key] = declared_elements(schema)
      targets = (schema.interfaces || [])
        .filter_map { |i| i.schema&.id }
        .map { |id| normalize(id) }
        .uniq
      @interfaces[key] = targets
    end

    def declared_elements(schema)
      index = {}
      schema.children.each do |element|
        if element.respond_to?(:id) && element.id
          index[normalize(element.id)] =
            true
        end
      end
      index
    end

    def visible_from_interfaces(key)
      (@interfaces[key] || []).flat_map do |target|
        @elements[target]&.keys || []
      end
    end

    def normalize(id)
      id&.downcase
    end
  end
end
