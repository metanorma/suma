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
  # elements, elements of schemas it interfaces to (with USE-FROM cascade),
  # the enclosing entity's own and inherited attributes (for entity-scoped
  # expressions), the enclosing rule's applies-to attributes and variables,
  # QUERY-bound variables, and the EXPRESS builtin vocabulary. Attribute
  # accesses (var.attr) are not schema-level references and are excluded.
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
      roles_of rolesof sin sizeof sqrt tan typeof usedin value value_in
      value_range value_list_by value_unique unique
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
      parsed = manifest.schemas.map do |entry|
        [entry, Expressir::Express::Parser.from_file(entry.path.to_s)]
      end
      corpus_entities = parsed.flat_map { |_, repo| Array(repo.schemas) }
        .flat_map do |schema|
          Array(schema.children).grep(Expressir::Model::Declarations::Entity)
        end
        .to_h { |entity| [entity.id.downcase, entity] }

      parsed.flat_map do |entry, repo|
        repo.schemas.flat_map do |schema|
          validate_schema(entry.path.to_s, schema, corpus_entities)
        end
      end
    end

    # All unresolved references in one schema.
    #
    # @param file [String] source file path (for diagnostics)
    # @param schema [Expressir::Model::Declarations::Schema]
    # @param corpus_entities [Hash{String=>Entity}] every entity of the
    #   corpus by downcased id, for cross-schema attribute inheritance
    # @return [Array<UnresolvedReference>]
    def validate_schema(file, schema, corpus_entities = {})
      violations = []
      scope = SchemaScope.new(schema, graph)
      entities = Array(schema.children).grep(Expressir::Model::Declarations::Entity)
        .to_h { |entity| [entity.id.downcase, entity] }

      Array(schema.interfaces).each do |interface|
        next if graph.schema_exists?(interface.schema.id)

        violations << unresolved(file, schema.id, schema.id, "interface",
                                 interface.schema.id,
                                 "interface target not declared")
      end

      Array(schema.children).each do |owner|
        violations.concat(declared_element_references(file, schema.id, owner,
                                                      scope, entities,
                                                      corpus_entities))
      end
      violations
    end

    private

    # Type- and structure-position references of one declared element.
    def declared_element_references(file, schema_id, owner, scope, entities,
                                    corpus_entities)
      refs = typed_references(owner, entities, corpus_entities)
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
    def typed_references(owner, entities, corpus_entities)
      case owner
      when Expressir::Model::Declarations::Entity
        entity_references(owner, entities, corpus_entities)
      when Expressir::Model::Declarations::Type then type_references(owner)
      when Expressir::Model::Declarations::Rule
        rule_references(owner)
      when Expressir::Model::Declarations::Constant
        datatype_references(owner.type, "constant")
      when Expressir::Model::Declarations::Function
        function_references(owner)
      when Expressir::Model::Declarations::SubtypeConstraint
        subtype_constraint_references(owner)
      else []
      end
    end

    def entity_references(entity, entities, corpus_entities)
      locals = attribute_scope(entity, entities, corpus_entities)
      refs = (entity.where_rules || []).flat_map do |rule|
        expression_references(rule.expression, "where", locals)
      end
      Array(entity.attributes).each do |attribute|
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
      refs = Array(rule.applies_to).map { |ref| ["rule_applies_to", ref.id] }
      locals = Array(rule.variables).filter_map do |variable|
        variable.id&.downcase
      end
      refs += (rule.where_rules || []).flat_map do |where|
        expression_references(where.expression, "where", locals)
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
      if constraint.applies_to.is_a?(Expressir::Model::References::SimpleReference)
        refs << ["subtype_constraint", constraint.applies_to.id]
      end
      Array(constraint.total_over).each do |ref|
        next unless ref.is_a?(Expressir::Model::References::SimpleReference)

        refs << ["total_over", ref.id]
      end
      if constraint.supertype_expression
        refs.concat(
          expression_references(constraint.supertype_expression, "supertype"),
        )
      end
      refs
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

    def expression_references(node, kind, locals = [])
      scoped = locals + query_variables(node) +
        attribute_access_identifiers(node)
      refs = []
      walk(node) do |child|
        next unless simple_reference?(child)
        next if child.id == "?"
        next if scoped.include?(child.id.to_s.downcase)

        refs << [kind, child.id]
      end
      refs
    end

    # QUERY expressions bind their variable inside the query; collect every
    # bound variable name in the tree so the walk can skip them.
    def query_variables(node)
      found = []
      walk(node) do |child|
        if child.is_a?(Expressir::Model::Expressions::QueryExpression) &&
            child.id
          found << child.id.to_s.downcase
        end
      end
      found
    end

    # Attribute accesses (var.attr, SELF\entity.attr) resolve against the
    # base value's type, not the schema — neither the accessed attribute
    # nor the base identifier is a schema-level reference.
    def attribute_access_identifiers(node)
      found = []
      walk(node) do |child|
        next unless child.is_a?(Expressir::Model::References::AttributeReference)

        collect_access_identifier(found, child.ref)
        collect_access_identifier(found, child.attribute)
      end
      found
    end

    def collect_access_identifier(found, part)
      return unless part.is_a?(Expressir::Model::References::SimpleReference)
      return unless part.id

      found << part.id.to_s.downcase
    end

    # Bare identifiers in an entity's expressions resolve against the
    # entity's own attributes and those inherited through its supertype
    # chain, following subtypes across schemas when the parent entity is
    # in the corpus (name-keyed; EXPRESS entity names are schema-scoped,
    # but cross-schema parents resolve through interface visibility, so
    # the name is the identity the child's source references).
    def attribute_scope(entity, entities, corpus_entities)
      names = []
      queue = [entity]
      seen = {}
      until queue.empty?
        current = queue.shift
        key = current.id.to_s.downcase
        next if seen[key]

        seen[key] = true
        Array(current.attributes).each do |attribute|
          names << attribute.id.downcase if attribute.id
        end
        supertype_references(current).each do |(kind, name)|
          next unless kind == "subtype_of"

          parent = entities[name.downcase] ||
            corpus_entities[name.downcase]
          queue << parent if parent
        end
      end
      names
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

        Array(schema.children).each { |declaration| add(declaration) }
        Array(schema.entities).each do |entity|
          Array(entity.attributes).each { |attribute| add(attribute) }
        end
        Array(schema.rules).each do |rule|
          Array(rule.variables).each { |variable| add(variable) }
          Array(rule.applies_to).each do |ref|
            entity = Array(schema.entities).find do |candidate|
              candidate.id&.downcase == ref.id&.downcase
            end
            next unless entity

            Array(entity.attributes).each { |attribute| add(attribute) }
          end
        end
        Array(schema.constants).each { |constant| add(constant) }
        Array(schema.functions).each do |function|
          Array(function.parameters).each { |parameter| add(parameter) }
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
