# frozen_string_literal: true

require "rdf"
require "rdf/turtle"
require "expressir"
# Expressir::SchemaManifest references Pathname without requiring it
# (expressir upstream gap); load it before any manifest parsing.
require "pathname"

module Suma
  # Projects an EXPRESS corpus into OWL (Turtle).
  #
  # Mapping:
  #   - entity              → owl:Class (labelled, isDefinedBy its schema)
  #   - subtype_of          → rdfs:subClassOf
  #   - SELECT type         → owl:Class + owl:unionOf member classes
  #   - ENUMERATION type    → owl:Class + owl:oneOf named individuals
  #   - explicit attribute  → owl:ObjectProperty (entity/select domains) or
  #                           owl:DatatypeProperty (simple domains),
  #                           attached to its owner class through an
  #                           owl:Restriction carrying cardinality
  #   - where rule          → rdfs:comment on the owning class
  #
  # IRIs derive from the corpus URN scheme via {Suma::Urn}:
  # +<base>:tech:<schema>.<element>+ for classes and
  # +<base>:tech:<schema>.<entity>.<attribute>+ for properties — the same
  # identity used by the terminology and register layers.
  #
  # Both a whole-corpus ontology and per-schema projections are available;
  # each projection is cached, so one instance parses the manifest once.
  class OwlProjection
    OWL = RDF::Vocabulary.new("http://www.w3.org/2002/07/owl#")
    RDFS = RDF::Vocabulary.new("http://www.w3.org/2000/01/rdf-schema#")
    XSD = RDF::Vocabulary.new("http://www.w3.org/2001/XMLSchema#")

    DATA_RANGES = {
      Expressir::Model::DataTypes::Boolean => XSD.boolean,
      Expressir::Model::DataTypes::Logical => XSD.boolean,
      Expressir::Model::DataTypes::Integer => XSD.integer,
      Expressir::Model::DataTypes::Number => XSD.double,
      Expressir::Model::DataTypes::Real => XSD.double,
      Expressir::Model::DataTypes::String => XSD.string,
      Expressir::Model::DataTypes::Binary => XSD.hexBinary,
    }.freeze

    BUILTIN_RANGES = {
      "BOOLEAN" => XSD.boolean,
      "LOGICAL" => XSD.boolean,
      "INTEGER" => XSD.integer,
      "NUMBER" => XSD.double,
      "REAL" => XSD.double,
      "STRING" => XSD.string,
      "BINARY" => XSD.hexBinary,
    }.freeze

    AGGREGATE_CLASSES = [
      Expressir::Model::DataTypes::Array,
      Expressir::Model::DataTypes::Bag,
      Expressir::Model::DataTypes::List,
      Expressir::Model::DataTypes::Set,
    ].freeze

    ATTRIBUTE_KINDS = %w[EXPLICIT DERIVED INVERSE].freeze

    # @param manifest_file [String] schema manifest path
    # @param urn [String] base URN before the :tech component, e.g.
    #   "urn:iso:std:iso:10303:-2:ed-2:en". A URN already ending in
    #   +:tech+ is accepted and normalised, so IRIs never double the
    #   component.
    def initialize(manifest_file, urn:)
      @manifest_file = File.expand_path(manifest_file)
      @urn = Urn.new(strip_tech(urn))
      @graphs = {}
      @schemas = load_schemas
      @elements = index_elements
    end

    # @return [Urn]
    attr_reader :urn

    # @return [Array<String>] schema ids in the manifest, sorted
    def schema_ids
      @schemas.keys.sort
    end

    # The projected ontology.
    #
    # @param schema_id [String, nil] restrict the projection to one schema
    # @return [RDF::Graph]
    def graph(schema_id: nil)
      key = schema_id&.downcase
      @graphs[key] ||= build_graph(key)
    end

    # @param schema_id [String, nil] restrict the projection to one schema
    # @return [String] Turtle serialization
    def to_turtle(schema_id: nil)
      graph(schema_id: schema_id).dump(:turtle, prefixes: default_prefixes)
    end

    # Structural validation of the projection: every entity/type is
    # materialized as a class, every restriction property is declared,
    # every class has a defining schema, and the superclass relation is
    # acyclic over the corpus.
    #
    # @param schema_id [String, nil] validate only one schema's projection
    # @return [Array<String>] problems (empty = valid)
    def validate(schema_id: nil)
      projected = if schema_id
                    key = normalize(schema_id)
                    unless @schemas.key?(key)
                      raise ArgumentError,
                            "unknown schema: #{schema_id}"
                    end

                    { key => @schemas[key] }
                  else
                    @schemas
                  end
      projected_graph = graph(schema_id: schema_id)
      problems = []
      problems.concat(validate_materialization(projected))
      problems.concat(validate_restrictions(projected_graph))
      problems.concat(validate_orphans(projected_graph))
      problems.concat(validate_superclasses(projected_graph))
      problems.concat(validate_acyclic_superclasses(projected_graph))
      problems
    end

    # @param schema_id [String]
    # @param element_id [String]
    # @return [String] class IRI
    def class_iri(schema_id, element_id)
      element_iri(schema_id, element_id)
    end

    # @param schema_id [String]
    # @param entity_id [String]
    # @param attribute_id [String]
    # @return [String] property IRI
    def property_iri(schema_id, entity_id, attribute_id)
      element_iri(schema_id, "#{entity_id}.#{attribute_id}")
    end

    private

    def strip_tech(urn)
      urn.to_s
        .delete_suffix(Urn::WILDCARD_SUFFIX)
        .delete_suffix(":#{Urn::TECH_COMPONENT}")
    end

    def normalize(id)
      id&.downcase
    end

    def load_schemas
      manifest = Expressir::SchemaManifest.from_file(@manifest_file)
      manifest.schemas.each_with_object({}) do |entry, map|
        repo = Expressir::Express::Parser.from_file(entry.path.to_s)
        repo.schemas.each { |schema| map[normalize(schema.id)] = schema }
      end
    end

    # [schema_key, element_id.downcase] → declaration, for entities and
    # named types only (enumeration items are also top-level children in
    # the Expressir model and must not shadow declarations).
    def index_elements
      @schemas.each_with_object({}) do |(schema_key, schema), map|
        schema.children.each do |element|
          next unless class_element?(element)

          map[[schema_key, normalize(element.id)]] = element
        end
      end
    end

    def class_element?(element)
      element.is_a?(Expressir::Model::Declarations::Entity) ||
        element.is_a?(Expressir::Model::Declarations::Type)
    end

    def default_prefixes
      {
        owl: OWL.to_uri.to_s,
        rdfs: RDFS.to_uri.to_s,
        rdf: RDF.to_uri.to_s,
        xsd: XSD.to_uri.to_s,
      }
    end

    def build_graph(schema_key)
      graph = RDF::Graph.new
      add_ontology_header(graph, schema_key)
      @schemas.each do |key, schema|
        next if schema_key && key != schema_key

        project_schema(graph, key, schema)
      end
      graph
    end

    # A corpus projection is one ontology importing every schema
    # ontology; a per-schema projection declares itself and imports the
    # schemas it interfaces to, mirroring USE FROM / REFERENCE.
    def add_ontology_header(graph, schema_key)
      ontology = if schema_key
                   @urn.for_schema(schema_key)
                 else
                   @urn.to_s
                 end
      graph << [RDF::URI(ontology), RDF.type, OWL.Ontology]
      if schema_key
        graph << [RDF::URI(ontology), RDFS.label, schema_key]
        interface_targets(@schemas[schema_key]).each do |target|
          graph << [RDF::URI(ontology), OWL.imports,
                    RDF::URI(@urn.for_schema(target))]
        end
      else
        @schemas.each_key do |key|
          graph << [RDF::URI(ontology), OWL.imports,
                    RDF::URI(@urn.for_schema(key))]
        end
      end
    end

    def interface_targets(schema)
      (schema.interfaces || []).filter_map { |i| i.schema&.id }.map do |id|
        normalize(id)
      end.uniq.sort
    end

    def project_schema(graph, schema_key, schema)
      schema.children.each do |element|
        case element
        when Expressir::Model::Declarations::Entity
          project_entity(graph, schema_key, element)
        when Expressir::Model::Declarations::Type
          project_type(graph, schema_key, element)
        end
      end
    end

    def project_entity(graph, schema_key, entity)
      iri = element_iri(schema_key, entity.id)
      add_class(graph, iri, entity.id, schema_key)
      add_remarks(graph, iri, entity)
      subtype_targets(entity).each do |target|
        graph << [RDF::URI(iri), RDFS.subClassOf,
                  RDF::URI(class_ref(target, schema_key))]
      end
      entity.attributes.to_a.each do |attribute|
        next unless ATTRIBUTE_KINDS.include?(attribute.kind.to_s.upcase)

        project_attribute(graph, iri, schema_key, entity, attribute)
      end
      add_where_rules(graph, iri, entity)
    end

    def project_type(graph, schema_key, type)
      iri = element_iri(schema_key, type.id)
      underlying = type.underlying_type
      if DATA_RANGES.key?(underlying.class)
        project_datatype(graph, iri, type, schema_key, underlying)
        return
      end

      add_class(graph, iri, type.id, schema_key)
      add_remarks(graph, iri, type)
      case underlying
      when Expressir::Model::DataTypes::Select
        project_select(graph, iri, schema_key, underlying)
      when Expressir::Model::DataTypes::Enumeration
        project_enumeration(graph, iri, schema_key, type)
      end
      add_where_rules(graph, iri, type)
    end

    # A defined type over a simple type is an rdfs:Datatype, not a class.
    def project_datatype(graph, iri, type, schema_key, underlying)
      graph << [RDF::URI(iri), RDF.type, RDFS.Datatype]
      graph << [RDF::URI(iri), RDFS.label, type.id.to_s]
      graph << [RDF::URI(iri), RDFS.isDefinedBy,
                RDF::URI(@urn.for_schema(schema_key))]
      graph << [RDF::URI(iri), RDFS.subClassOf, DATA_RANGES[underlying.class]]
      add_remarks(graph, iri, type)
      add_where_rules(graph, iri, type)
    end

    def add_class(graph, iri, name, schema_key)
      graph << [RDF::URI(iri), RDF.type, OWL.Class]
      graph << [RDF::URI(iri), RDFS.label, name.to_s]
      graph << [RDF::URI(iri), RDFS.isDefinedBy,
                RDF::URI(@urn.for_schema(schema_key))]
    end

    def add_remarks(graph, iri, element)
      Array(element.remarks).each do |remark|
        graph << [RDF::URI(iri), RDFS.comment, remark.to_s]
      end
    end

    def add_where_rules(graph, iri, element)
      (element.where_rules || []).each do |rule|
        graph << [RDF::URI(iri), RDFS.comment,
                  (rule.source || "WHERE #{rule.id}").to_s.strip]
      end
    end

    def project_select(graph, iri, schema_key, select)
      members = (select.items || []).map do |item|
        RDF::URI(class_ref(item.id, schema_key))
      end
      graph << [RDF::URI(iri), OWL.unionOf, list_head(iri, members)]
      append_list(graph, iri, members)
    end

    def project_enumeration(graph, iri, schema_key, type)
      individuals = (type.underlying_type.items || []).map do |item|
        individual = individual_iri(schema_key, type.id, item.id)
        graph << [RDF::URI(individual), RDF.type, OWL.NamedIndividual]
        graph << [RDF::URI(individual), RDF.type, RDF::URI(iri)]
        graph << [RDF::URI(individual), RDFS.label, item.id.to_s]
        RDF::URI(individual)
      end
      graph << [RDF::URI(iri), OWL.oneOf, list_head(iri, individuals)]
      append_list(graph, iri, individuals)
    end

    def project_attribute(graph, class_iri, schema_key, entity, attribute)
      iri = property_iri(schema_key, entity.id, attribute.id)
      target = attribute_target(attribute.type, schema_key)
      kind = target[:datatype] ? OWL.DatatypeProperty : OWL.ObjectProperty
      graph << [RDF::URI(iri), RDF.type, kind]
      graph << [RDF::URI(iri), RDFS.label, attribute.id.to_s]
      graph << [RDF::URI(iri), RDFS.domain, RDF::URI(class_iri)]
      graph << [RDF::URI(iri), RDFS.range, target[:range]]
      annotate_attribute(graph, iri, attribute)
      add_restriction(graph, class_iri, iri, attribute, target)
    end

    # Derived and inverse attributes are unformalized constraints: keep
    # their EXPRESS clause as a comment on the property.
    def annotate_attribute(graph, iri, attribute)
      prefix = case attribute.kind.to_s.upcase
               when "DERIVED" then "DERIVE"
               when "INVERSE" then "INVERSE"
               end
      return unless prefix

      graph << [RDF::URI(iri), RDFS.comment,
                "#{prefix} #{attribute.source || attribute.id}"]
    end

    def add_restriction(graph, class_iri, property_iri, attribute, target)
      node = RDF::URI(restriction_iri(property_iri))
      graph << [RDF::URI(class_iri), RDFS.subClassOf, node]
      graph << [node, RDF.type, OWL.Restriction]
      graph << [node, OWL.onProperty, RDF::URI(property_iri)]
      add_cardinality(graph, node, attribute, target)
    end

    def restriction_iri(property_iri)
      "#{property_iri}.restriction"
    end

    def add_cardinality(graph, node, attribute, target)
      if target[:aggregate]
        graph << [node, OWL.minCardinality,
                  count_literal(aggregate_bound(attribute.type, :bound1) || 0)]
        max = aggregate_bound(attribute.type, :bound2)
        graph << [node, OWL.maxCardinality, count_literal(max)] if max
      elsif attribute.optional || attribute.kind.to_s.upcase == "INVERSE"
        graph << [node, OWL.minCardinality, count_literal(0)]
      else
        graph << [node, OWL.cardinality, count_literal(1)]
      end
    end

    def count_literal(value)
      RDF::Literal.new(value, datatype: XSD.nonNegativeInteger)
    end

    # Aggregate bounds are integer literals; the upper bound may also be
    # the unbounded marker "?" (a SimpleReference), which yields nil.
    def aggregate_bound(type, method)
      bound = type.public_send(method)
      return nil unless bound.is_a?(Expressir::Model::Literals::Integer)

      Integer(bound.value, exception: false)
    end

    # Resolve an attribute's declared type to { datatype:, range: }.
    def attribute_target(type, schema_key)
      case type
      when Expressir::Model::References::SimpleReference
        simple_reference_target(type.id, schema_key)
      when *AGGREGATE_CLASSES
        attribute_target(type.base_type, schema_key).merge(aggregate: true)
      else
        datatype_range(type)
      end
    end

    def simple_reference_target(name, schema_key)
      declaration = @elements[[schema_key, normalize(name)]]
      if declaration
        declaration_target(declaration, schema_key)
      elsif (range = BUILTIN_RANGES[name.to_s.upcase])
        { datatype: true, range: range }
      else
        { datatype: false, range: RDF::URI(class_ref(name, schema_key)) }
      end
    end

    def declaration_target(declaration, schema_key)
      if declaration.is_a?(Expressir::Model::Declarations::Entity)
        { datatype: false,
          range: RDF::URI(element_iri(schema_key, declaration.id)) }
      else
        underlying = declaration.underlying_type
        { datatype: DATA_RANGES.key?(underlying.class),
          range: RDF::URI(element_iri(schema_key, declaration.id)) }
      end
    end

    def datatype_range(type)
      { datatype: true, range: DATA_RANGES.fetch(type.class, XSD.string) }
    end

    def subtype_targets(entity)
      Array(entity.subtype_of).filter_map do |ref|
        ref.id if ref.is_a?(Expressir::Model::References::SimpleReference)
      end
    end

    # Resolve a class name to its corpus IRI. Local declarations win;
    # otherwise any corpus schema declaring the name is used (EXPRESS
    # brings interfaced elements into scope unqualified).
    def class_ref(name, schema_key)
      local = @elements[[schema_key, normalize(name)]]
      return element_iri(schema_key, local.id) if local

      found = @elements.keys
        .select { |(_, element_id)| element_id == normalize(name) }
        .min
      if found
        element_iri(found.first, @elements[found].id)
      else
        @urn.for_entity(name)
      end
    end

    def element_iri(schema_id, element_id)
      @urn.for_entity("#{schema_id}.#{element_id}")
    end

    def individual_iri(schema_id, type_id, item_id)
      @urn.for_entity("#{schema_id}.#{type_id}.#{item_id}")
    end

    def list_head(owner_iri, items)
      return RDF.nil if items.empty?

      RDF::URI("#{owner_iri}.members.0")
    end

    # Named cons cells keep the ontology free of blank nodes, so parallel
    # projections are comparable and serialization is reproducible.
    def append_list(graph, owner_iri, items)
      items.each_with_index do |item, index|
        cell = RDF::URI("#{owner_iri}.members.#{index}")
        graph << [cell, RDF.first, item]
        rest = if index == items.length - 1
                 RDF.nil
               else
                 RDF::URI("#{owner_iri}.members.#{index + 1}")
               end
        graph << [cell, RDF.rest, rest]
      end
    end

    def validate_materialization(projected)
      projected.flat_map do |schema_key, schema|
        schema.children.filter_map do |element|
          next unless class_element?(element)

          iri = element_iri(schema_key, element.id)
          next if declaration?(graph(schema_id: schema_key),
                               [RDF::URI(iri), RDF.type, OWL.Class])
          next if declaration?(graph(schema_id: schema_key),
                               [RDF::URI(iri), RDF.type, RDFS.Datatype])

          "missing class or datatype for #{schema_key}.#{element.id}"
        end
      end
    end

    def validate_restrictions(projected_graph)
      matching(projected_graph, [nil, OWL.onProperty, nil])
        .filter_map do |statement|
          property = statement.object
          next if matching(projected_graph,
                           [property, RDF.type, OWL.ObjectProperty]).any?
          next if matching(projected_graph,
                           [property, RDF.type, OWL.DatatypeProperty]).any?

          "restriction property not declared: #{property}"
        end
    end

    # Every class and datatype must name a schema ontology of the corpus
    # through rdfs:isDefinedBy; anything else is an orphan.
    def validate_orphans(projected_graph)
      schema_ontologies = @schemas.keys.to_h do |key|
        [@urn.for_schema(key), true]
      end
      declarations = matching(projected_graph, [nil, RDF.type, OWL.Class]) +
        matching(projected_graph, [nil, RDF.type, RDFS.Datatype])

      declarations.filter_map do |statement|
        subject = statement.subject
        definitions = matching(projected_graph,
                               [subject, RDFS.isDefinedBy, nil])
        next "orphan class without defining schema: #{subject}" if
          definitions.empty?

        known = definitions.any? do |definition|
          definition.object.is_a?(RDF::URI) &&
            schema_ontologies.key?(definition.object.to_s)
        end
        "class defined by unknown schema: #{subject}" unless known
      end
    end

    def validate_superclasses(projected_graph)
      corpus_classes = {}
      @elements.each_key do |schema_key, element_id|
        corpus_classes[element_iri(schema_key, element_id)] = true
      end

      matching(projected_graph, [nil, RDFS.subClassOf, nil])
        .filter_map do |statement|
          superclass = statement.object
          next unless superclass.is_a?(RDF::URI)
          next if restriction_node?(projected_graph, superclass)
          next if datatype_node?(projected_graph, statement.subject)
          next if corpus_classes.key?(superclass.to_s)

          "superclass without class declaration: #{superclass}"
        end
    end

    # Restriction nodes are blank, so superclass edges between URI nodes
    # are the declared EXPRESS subtype relation; EXPRESS forbids cycles,
    # and a cycle here means the projection is unsound.
    def validate_acyclic_superclasses(projected_graph)
      edges = {}
      matching(projected_graph, [nil, RDFS.subClassOf, nil]).each do |statement|
        subject = statement.subject
        object = statement.object
        next unless subject.is_a?(RDF::URI) && object.is_a?(RDF::URI)
        next if restriction_node?(projected_graph, object)

        (edges[subject.to_s] ||= []) << object.to_s
      end

      cycles = []
      visited = {}
      edges.each_key do |start|
        detect_cycle(start, edges, visited, cycles)
      end
      cycles.uniq.map { |node| "superclass cycle involving #{node}" }
    end

    # RDF::Queryable#query returns nil when a pattern has no matches, so
    # collect through the block form instead of chaining on the result.
    def matching(graph, pattern)
      results = []
      graph.query(pattern) { |statement| results << statement }
      results
    end

    def restriction_node?(graph, term)
      term.is_a?(RDF::URI) &&
        matching(graph, [term, RDF.type, OWL.Restriction]).any?
    end

    # Datatype aliases are declared rdfs:subClassOf their XSD range, so
    # their superclass is intentionally outside the corpus class set.
    def datatype_node?(graph, term)
      term.is_a?(RDF::URI) &&
        matching(graph, [term, RDF.type, RDFS.Datatype]).any?
    end

    def declaration?(graph, pattern)
      matching(graph, pattern).any?
    end

    def detect_cycle(node, edges, visited, cycles)
      return if visited[node] == :done
      return cycles << node if visited[node] == :visiting

      visited[node] = :visiting
      (edges[node] || []).each do |child|
        detect_cycle(child, edges, visited, cycles)
      end
      visited[node] = :done
    end
  end
end
