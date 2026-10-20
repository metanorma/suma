# frozen_string_literal: true

require "expressir"
# Expressir::SchemaManifest references Pathname without requiring it
# (expressir upstream gap); load it before any manifest parsing.
require "pathname"

module Suma
  # S1 referential closure: extracts every EXPRESS-internal reference from
  # a schema collection and resolves it against the {CorpusGraph}.
  #
  # Reference classes covered (one predicate, many extractors):
  # attribute domains, SELECT/AGGREGATE branches, where-rule expressions,
  # subtype constraints, supertype/subtype lists, rule applies-to targets,
  # and inter-schema interfaces.
  #
  # A reference resolves against, in order: the enclosing schema's declared
  # elements, elements of schemas it interfaces to, the enclosing entity's
  # own attributes (for entity-scoped expressions), the enclosing rule's
  # applies-to attributes and variables, and the EXPRESS builtin vocabulary.
  #
  # The predicate is zero-tolerance: any unresolved reference is a
  # violation, and `violations.empty?` is the corpus well-formedness gate.
  class ClosureValidator
    UnresolvedReference = Struct.new(:file, :line, :schema_id, :owner_id,
                                     :kind, :reference, :reason,
                                     keyword_init: true)

    # Attributes that hold resolved links rather than syntactic children.
    # Traversing them would walk the whole resolved graph (and its cycles)
    # instead of the expression/type tree.
    RESOLUTION_LINK_ATTRIBUTES = %i[ref entity].freeze

    BUILTIN_IDENTIFIERS = %w[
      abs acos asin atan atan2 bexists blength const_e cos exists exp
      format hibound hiindex length lobound loindex log log2 log10 nvl odd
      roles_of sin sizeof sqrt tan typeof usedin value value_in
      value_range value_list_by unique
      self and or xor not in like equal instanceof
      e pi
    ].freeze

    attr_reader :graph

    # @param graph [CorpusGraph]
    def initialize(graph)
      @graph = graph
      @source_lines = {}
    end

    # Validate every schema of the manifest.
    #
    # @param manifest_file [String] schema manifest path
    # @return [Array<UnresolvedReference>]
    def validate_manifest(manifest_file)
      manifest = Expressir::SchemaManifest.from_file(
        File.expand_path(manifest_file),
      )
      manifest.schemas.flat_map do |entry|
        repo = Expressir::Express::Parser.from_file(entry.path.to_s)
        repo.schemas.flat_map do |schema|
          validate_schema(entry.path.to_s, schema)
        end
      end
    end

    # All unresolved references in one schema.
    #
    # @param file [String] source file path (for diagnostics)
    # @param schema [Expressir::Model::Declarations::Schema]
    # @return [Array<UnresolvedReference>]
    def validate_schema(file, schema)
      violations = []
      scope = SchemaScope.new(schema, graph)

      schema.interfaces.each do |interface|
        next if graph.schema_exists?(interface.schema.id)

        violations << unresolved(file, schema.id, schema.id, "interface",
                                 interface.schema.id,
                                 "interface target not declared")
      end

      schema.children.each do |owner|
        violations.concat(declared_element_references(file, schema.id, owner,
                                                      scope))
      end
      violations
    end

    private

    # Type- and structure-position references of one declared element.
    def declared_element_references(file, schema_id, owner, scope)
      refs = typed_references(owner)
      refs.filter_map do |(kind, identifier)|
        if resolvable?(identifier, scope)
          nil
        else
          unresolved(
            file, schema_id, owner_id_of(owner), kind, identifier,
            "'#{identifier}' is not declared in this schema, its " \
            "interfaces, or the EXPRESS builtins"
          )
        end
      end
    end

    # (kind, identifier) pairs from every position of one declaration.
    def typed_references(owner)
      case owner
      when Expressir::Model::Declarations::Entity then entity_references(owner)
      when Expressir::Model::Declarations::Type then type_references(owner)
      when Expressir::Model::Declarations::Rule then rule_references(owner)
      when Expressir::Model::Declarations::Constant
        datatype_references(owner.type, "constant")
      when Expressir::Model::Declarations::Function
        function_references(owner)
      when Expressir::Model::Declarations::SubtypeConstraint
        subtype_constraint_references(owner)
      else []
      end
    end

    def entity_references(entity)
      refs = (entity.where_rules || []).flat_map do |rule|
        expression_references(rule.expression, "where")
      end
      entity.attributes.each do |attribute|
        refs.concat(datatype_references(attribute.type, "attribute"))
      end
      refs.concat(supertype_references(entity))
    end

    def type_references(type)
      refs = (type.where_rules || []).flat_map do |rule|
        expression_references(rule.expression, "where")
      end
      refs.concat(datatype_references(type.underlying_type, "underlying"))
    end

    def rule_references(rule)
      refs = rule.applies_to.map { |ref| ["rule_applies_to", ref.id] }
      refs += (rule.where_rules || []).flat_map do |where|
        expression_references(where.expression, "where")
      end
      refs += (rule.variables || []).flat_map do |variable|
        datatype_references(variable.type, "variable")
      end
      refs
    end

    def function_references(function)
      refs = (function.parameters || []).flat_map do |parameter|
        datatype_references(parameter.type, "parameter")
      end
      if function.return_type
        refs.concat(datatype_references(function.return_type, "return"))
      end
      refs
    end

    def subtype_constraint_references(constraint)
      refs = []
      refs << ["subtype_constraint", constraint.entity.id] if constraint.entity
      refs.concat(supertype_references(constraint))
    end

    def supertype_references(owner)
      refs = []
      (owner.subtype_of || []).each do |ref|
        refs << ["subtype_of", ref.id] if ref.respond_to?(:id) && ref.id
      end
      if owner.respond_to?(:supertype_expression) && owner.supertype_expression
        refs.concat(expression_references(owner.supertype_expression,
                                          "supertype"))
      end
      refs
    end

    # (kind, identifier) pairs from a datatype or expression tree.
    def datatype_references(node, kind)
      expression_references(node, kind)
    end

    def expression_references(node, kind)
      refs = []
      walk(node) do |child|
        refs << [kind, child.id] if simple_reference?(child)
      end
      refs
    end

    def simple_reference?(node)
      node.is_a?(Expressir::Model::References::SimpleReference) &&
        !node.id.nil?
    end

    # Depth-first walk over the syntactic tree of a model element.
    # Expressir only implements `children` on some classes, so traversal
    # goes through the lutaml-model attribute definitions: every attribute
    # whose value is a ModelElement (or a collection of them) is a child.
    # The model graph has reference cycles, so visited nodes are tracked
    # by identity.
    def walk(node, seen = {}.compare_by_identity, &block)
      return unless node.is_a?(Expressir::Model::ModelElement)
      return if seen.key?(node)

      seen[node] = true
      yield node
      each_model_child(node) { |child| walk(child, seen, &block) }
    end

    def each_model_child(node)
      node.class.attributes.each_key do |name|
        next if RESOLUTION_LINK_ATTRIBUTES.include?(name)

        value = begin
          node.public_send(name)
        rescue StandardError
          next
        end
        values = value.is_a?(Array) ? value : [value]
        values.each do |child|
          yield child if child.is_a?(Expressir::Model::ModelElement)
        end
      end
    end

    # A reference resolves when its root identifier is declared in the
    # schema, visible through an interface, or is an EXPRESS builtin.
    def resolvable?(identifier, scope)
      root = identifier.split(".").first.downcase
      return true if BUILTIN_IDENTIFIERS.include?(root)

      scope.visible?(root)
    end

    def unresolved(file, schema_id, owner_id, kind, reference, reason)
      UnresolvedReference.new(
        file: file,
        line: approximate_line(file, reference),
        schema_id: schema_id,
        owner_id: owner_id,
        kind: kind,
        reference: reference,
        reason: reason,
      )
    end

    # Expressir's Ruby model carries no source positions, so diagnostics
    # approximate the line by the first token occurrence in the file.
    def approximate_line(file, identifier)
      lines = (@source_lines[file] ||= read_source(file))
      token = identifier.split(".").first
      pattern = /\b#{Regexp.escape(token)}\b/i
      index = lines.index { |line| line.match?(pattern) }
      index ? index + 1 : nil
    end

    def read_source(file)
      File.readlines(file)
    rescue StandardError
      []
    end

    def owner_id_of(owner)
      owner.respond_to?(:id) && owner.id ? owner.id : "(anonymous)"
    end

    # Names visible for expression resolution inside one schema: declared
    # elements, the attributes of every entity, rule applies-to entity
    # attributes, rule variables, constants, and function parameters.
    # Only declarations are collected — expression contents are the very
    # references being validated and must never enter the scope.
    class SchemaScope
      def initialize(schema, graph)
        @names = {}
        @graph = graph
        @schema_id = schema.id

        schema.children.each { |declaration| add(declaration) }
        schema.entities.each do |entity|
          entity.attributes.each { |attribute| add(attribute) }
        end
        schema.rules.each do |rule|
          rule.variables.each { |variable| add(variable) }
          rule.applies_to.each do |ref|
            entity = schema.entities.find do |candidate|
              candidate.id&.downcase == ref.id&.downcase
            end
            next unless entity

            entity.attributes.each { |attribute| add(attribute) }
          end
        end
        schema.constants.each { |constant| add(constant) }
        schema.functions.each do |function|
          (function.parameters || []).each { |parameter| add(parameter) }
        end
      end

      def visible?(name)
        @names[name.downcase] ||
          @graph.element_visible?(@schema_id, name)
      end

      private

      def add(node)
        return unless node.respond_to?(:id) && node.id

        @names[node.id.downcase] = true
      end
    end
  end
end
