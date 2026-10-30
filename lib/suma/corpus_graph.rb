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
    # One USE/REFERENCE import: the target schema, its kind, and the named
    # items (renames already applied — the visible name is +items+).
    InterfaceEdge = Struct.new(:kind, :target, :items, keyword_init: true)

    EMPTY_VISIBLE = {}.freeze

    attr_reader :schema_ids

    def initialize(repositories)
      @schemas = {}
      @elements = {}
      @interfaces = {}

      repositories.each do |repo|
        repo.schemas.each { |schema| add_schema(schema) }
      end
      @schema_ids = @schemas.keys
      @visibility = build_visibility
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

    # Does +schema_id+ (or the schemas it imports) declare +element_id+?
    # EXPRESS resolves unqualified names against the local schema and the
    # schema's interface visibility, including USE-FROM cascades.
    #
    # @param schema_id [String]
    # @param element_id [String]
    # @return [Boolean]
    def element_visible?(schema_id, element_id)
      key = normalize(schema_id)
      return false unless @visibility.key?(key)

      @visibility[key].key?(normalize(element_id))
    end

    # Schemas that +schema_id+ USEs FROM or REFERENCEs.
    #
    # @param schema_id [String]
    # @return [Array<String>] normalized ids of interface targets
    def interface_targets(schema_id)
      (@interfaces[normalize(schema_id)] || []).map(&:target)
    end

    # Transitive interface closure: every schema +schema_id+ depends on,
    # directly or through other schemas.
    #
    # @param schema_id [String]
    # @return [Array<String>] normalized ids (excluding +schema_id+)
    def dependency_closure(schema_id)
      seen = {}
      queue = interface_targets(schema_id).dup
      until queue.empty?
        id = queue.shift
        next if seen.key?(id)

        seen[id] = true
        queue.concat(interface_targets(id))
      end
      seen.keys
    end

    # Schemas that transitively depend on +schema_id+ — the reverse of
    # {#dependency_closure}; used by change-impact analysis (S3).
    #
    # @param schema_id [String]
    # @return [Array<String>] normalized ids, sorted
    def dependents_of(schema_id)
      target = normalize(schema_id)
      @schemas.keys
        .reject { |candidate| candidate == target }
        .select do |candidate|
          dependency_closure(candidate).include?(target)
        end
        .sort
    end

    private

    def add_schema(schema)
      key = normalize(schema.id)
      @schemas[key] = true
      @elements[key] = declared_elements(schema)
      @interfaces[key] = Array(schema.interfaces).filter_map do |interface|
        build_edge(interface)
      end
    end

    def build_edge(interface)
      target = interface.schema&.id
      return nil unless target

      items = Array(interface.items).filter_map do |item|
        item.id || (item.ref.id if item.ref.respond_to?(:id))
      end
      InterfaceEdge.new(kind: interface.kind.to_s,
                        target: normalize(target),
                        items: items)
    end

    def declared_elements(schema)
      index = {}
      Array(schema.children).each do |element|
        if element.respond_to?(:id) && element.id
          index[normalize(element.id)] =
            true
        end
      end
      index
    end

    # EXPRESS interface visibility (ISO 10303-11 §13.3): a schema sees its
    # declarations plus its imports. An unrestricted USE re-exports
    # everything its target makes visible, so visibility cascades through
    # USE chains; a named import exposes only the named (renamed) items;
    # a REFERENCE exposes the target's declarations without cascading.
    #
    # WG12 corpora ship circular USE interfaces, so this is a monotone
    # fixed-point iteration — sound under cycles, and each pass only adds.
    def build_visibility
      visible = {}
      @schemas.each_key { |key| visible[key] = (@elements[key] || {}).dup }

      changed = true
      while changed
        changed = false
        @schemas.each_key do |key|
          changed ||= apply_visibility_pass(key, visible)
        end
      end
      visible
    end

    def apply_visibility_pass(key, visible)
      names = visible[key]
      changed = false
      (@interfaces[key] || []).each do |edge|
        next unless @schemas.key?(edge.target)

        changed ||= import_edge_names(names, edge, visible)
      end
      changed
    end

    def import_edge_names(names, edge, visible)
      changed = false
      imported_names(edge, visible).each_key do |name|
        next if names.key?(name)

        names[name] = true
        changed = true
      end
      changed
    end

    def imported_names(edge, visible)
      if edge.items.any?
        edge.items.to_h { |name| [normalize(name), true] }
      elsif edge.kind == "USE"
        visible[edge.target] || EMPTY_VISIBLE
      else
        @elements[edge.target] || EMPTY_VISIBLE
      end
    end

    def normalize(id)
      id&.downcase
    end
  end
end
