# frozen_string_literal: true

require "expressir"

module Suma
  # Pre-built index for O(1) schema and element lookup.
  # Build once from a parsed repo, then query by name.
  class SchemaIndex
    def initialize(repo)
      @schemas_by_name = {}
      @elements_by_schema = {}

      repo.schemas.each do |schema|
        key = schema.id.downcase
        @schemas_by_name[key] = schema
        @elements_by_schema[key] = build_element_index(schema)
      end
    end

    def find_schema(name)
      @schemas_by_name[name.downcase]
    end

    def find_element(schema_name, element_name)
      elements = @elements_by_schema[schema_name.downcase]
      elements&.[](element_name.downcase)
    end

    private

    def build_element_index(schema)
      index = {}

      element_collections(schema).each do |collection|
        collection&.each { |e| index[e.id.downcase] = e }
      end

      index
    end

    def element_collections(schema)
      [
        schema.entities,
        schema.types,
        schema.constants,
        schema.functions,
        schema.rules,
        schema.procedures,
        schema.subtype_constraints,
      ]
    end
  end
end
