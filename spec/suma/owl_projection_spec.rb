# frozen_string_literal: true

require "spec_helper"
require "suma/owl_projection"
require "rdf/turtle"

RSpec.describe Suma::OwlProjection do
  subject(:projection) { described_class.new(manifest, urn: base_urn) }

  let(:manifest) { File.expand_path("../fixtures/owl/schemas.yaml", __dir__) }
  let(:base_urn) { "urn:example:owl:example:ed-1:en" }
  let(:ns) { "#{base_urn}:tech:example_schema" }
  let(:owl) { described_class::OWL }
  let(:rdfs) { described_class::RDFS }
  let(:xsd) { described_class::XSD }
  let(:graph) { projection.graph }

  def iri(id)
    "#{ns}.#{id}"
  end

  def triple?(subject, predicate, object)
    graph.include?(RDF::Statement.new(RDF::URI(subject),
                                      predicate,
                                      object))
  end

  def count(value)
    RDF::Literal.new(value, datatype: xsd.nonNegativeInteger)
  end

  # Compare by term text: parsed literals and constructed literals with
  # the same lexical form and datatype are separate Ruby classes.
  def triple_strings(source)
    source.map do |statement|
      [statement.subject.to_s, statement.predicate.to_s,
       statement.object.to_s]
    end.sort
  end

  describe "classes" do
    it "declares every entity as an owl:Class" do
      %w[part bolt nut assembly].each do |entity|
        expect(graph).to include(
          RDF::Statement.new(RDF::URI(iri(entity)), RDF.type, owl.Class),
        )
      end
    end

    it "labels classes and points them at their defining schema" do
      expect(triple?(iri("part"), rdfs.label, RDF::Literal("part"))).to be true
      expect(graph).to include(
        RDF::Statement.new(RDF::URI(iri("part")), rdfs.isDefinedBy,
                           RDF::URI("#{base_urn}:tech:example_schema")),
      )
    end

    it "projects subtype_of as rdfs:subClassOf" do
      expect(graph).to include(
        RDF::Statement.new(RDF::URI(iri("bolt")), rdfs.subClassOf,
                           RDF::URI(iri("part"))),
      )
      expect(graph).to include(
        RDF::Statement.new(RDF::URI(iri("nut")), rdfs.subClassOf,
                           RDF::URI(iri("part"))),
      )
    end
  end

  describe "defined types" do
    it "projects a simple type alias as an rdfs:Datatype" do
      expect(graph).to include(
        RDF::Statement.new(RDF::URI(iri("label_type")), RDF.type,
                           rdfs.Datatype),
      )
      expect(graph).to include(
        RDF::Statement.new(RDF::URI(iri("label_type")), rdfs.subClassOf,
                           xsd.string),
      )
    end

    it "uses the datatype alias as an attribute range" do
      expect(graph).to include(
        RDF::Statement.new(RDF::URI(iri("part.name")), rdfs.range,
                           RDF::URI(iri("label_type"))),
      )
    end

    it "projects a SELECT as an owl:unionOf list of member classes" do
      expect(graph).to include(
        RDF::Statement.new(RDF::URI(iri("item_select")), owl.unionOf,
                           RDF::URI(iri("item_select.members.0"))),
      )
      expect(graph).to include(
        RDF::Statement.new(RDF::URI(iri("item_select.members.0")),
                           RDF.first, RDF::URI(iri("part"))),
      )
      expect(graph).to include(
        RDF::Statement.new(RDF::URI(iri("item_select.members.1")),
                           RDF.first, RDF::URI(iri("assembly"))),
      )
      expect(graph).to include(
        RDF::Statement.new(RDF::URI(iri("item_select.members.1")),
                           RDF.rest, RDF.nil),
      )
    end

    it "projects an enumeration as owl:oneOf named individuals" do
      expect(graph).to include(
        RDF::Statement.new(RDF::URI(iri("status")), owl.oneOf,
                           RDF::URI(iri("status.members.0"))),
      )
      %w[active inactive].each do |item|
        individual = RDF::URI(iri("status.#{item}"))
        expect(graph).to include(
          RDF::Statement.new(individual, RDF.type, owl.NamedIndividual),
        )
        expect(graph).to include(
          RDF::Statement.new(individual, RDF.type, RDF::URI(iri("status"))),
        )
        expect(triple?(iri("status.#{item}"), rdfs.label,
                       RDF::Literal(item))).to be true
      end
    end
  end

  describe "attributes" do
    it "projects simple attributes as datatype properties" do
      expect(graph).to include(
        RDF::Statement.new(RDF::URI(iri("part.weight")), RDF.type,
                           owl.DatatypeProperty),
      )
      expect(graph).to include(
        RDF::Statement.new(RDF::URI(iri("part.weight")), rdfs.range,
                           xsd.double),
      )
    end

    it "projects entity-valued attributes as object properties" do
      expect(graph).to include(
        RDF::Statement.new(RDF::URI(iri("assembly.components")), RDF.type,
                           owl.ObjectProperty),
      )
      expect(graph).to include(
        RDF::Statement.new(RDF::URI(iri("assembly.components")), rdfs.range,
                           RDF::URI(iri("part"))),
      )
    end

    it "declares the owning class as the property domain" do
      expect(graph).to include(
        RDF::Statement.new(RDF::URI(iri("part.weight")), rdfs.domain,
                           RDF::URI(iri("part"))),
      )
    end

    it "attaches each property through an owl:Restriction" do
      restriction = RDF::URI(iri("part.weight.restriction"))
      expect(graph).to include(
        RDF::Statement.new(RDF::URI(iri("part")), rdfs.subClassOf,
                           restriction),
      )
      expect(graph).to include(
        RDF::Statement.new(restriction, RDF.type, owl.Restriction),
      )
      expect(graph).to include(
        RDF::Statement.new(restriction, owl.onProperty,
                           RDF::URI(iri("part.weight"))),
      )
    end

    it "marks mandatory attributes with owl:cardinality 1" do
      expect(graph).to include(
        RDF::Statement.new(RDF::URI(iri("part.weight.restriction")),
                           owl.cardinality, count(1)),
      )
    end

    it "marks optional attributes with owl:minCardinality 0" do
      expect(graph).to include(
        RDF::Statement.new(RDF::URI(iri("part.note.restriction")),
                           owl.minCardinality, count(0)),
      )
    end

    it "uses aggregate bounds for cardinality" do
      expect(graph).to include(
        RDF::Statement.new(RDF::URI(iri("part.tags.restriction")),
                           owl.minCardinality, count(0)),
      )
      expect(graph).to include(
        RDF::Statement.new(RDF::URI(iri("assembly.components.restriction")),
                           owl.minCardinality, count(1)),
      )
      expect(graph).to include(
        RDF::Statement.new(RDF::URI(iri("part.sides.restriction")),
                           owl.minCardinality, count(2)),
      )
      expect(graph).to include(
        RDF::Statement.new(RDF::URI(iri("part.sides.restriction")),
                           owl.maxCardinality, count(6)),
      )
    end

    it "annotates WHERE rules on the owning class" do
      expect(graph).to include(
        RDF::Statement.new(RDF::URI(iri("part")), rdfs.comment,
                           RDF::Literal("positive_weight: weight > 0.0;")),
      )
    end

    it "projects derived attributes as annotated properties" do
      expect(graph).to include(
        RDF::Statement.new(RDF::URI(iri("part.tag_count")), RDF.type,
                           owl.DatatypeProperty),
      )
      expect(graph).to include(
        RDF::Statement.new(
          RDF::URI(iri("part.tag_count")), rdfs.comment,
          RDF::Literal("DERIVE tag_count : INTEGER := SIZEOF(tags);")
        ),
      )
      expect(graph).to include(
        RDF::Statement.new(RDF::URI(iri("part.tag_count.restriction")),
                           owl.cardinality, count(1)),
      )
    end

    it "projects inverse attributes as annotated object properties" do
      expect(graph).to include(
        RDF::Statement.new(RDF::URI(iri("part.assemblies")), RDF.type,
                           owl.ObjectProperty),
      )
      expect(graph).to include(
        RDF::Statement.new(RDF::URI(iri("part.assemblies")), rdfs.range,
                           RDF::URI(iri("assembly"))),
      )
      expect(graph).to include(
        RDF::Statement.new(
          RDF::URI(iri("part.assemblies")), rdfs.comment,
          RDF::Literal(
            "INVERSE assemblies : SET [0:?] OF assembly FOR components;",
          )
        ),
      )
      expect(graph).to include(
        RDF::Statement.new(RDF::URI(iri("part.assemblies.restriction")),
                           owl.minCardinality, count(0)),
      )
    end
  end

  describe "scoping" do
    let(:manifest) do
      File.expand_path("../fixtures/ap_publication/schemas.yaml", __dir__)
    end
    let(:base_urn) { "urn:iso:std:iso:10303:-2:ed-2:en" }

    it "projects every schema of the corpus by default" do
      expect(projection.schema_ids).to eq(
        %w[ap_gizmo_arm ap_gizmo_mim gizmo_arm widget_schema],
      )
      expect(projection.graph(schema_id: "gizmo_arm")).to include(
        RDF::Statement.new(
          RDF::URI("#{base_urn}:tech:gizmo_arm.gizmo"),
          RDF::type, described_class::OWL.Class
        ),
      )
      expect(projection.graph(schema_id: "widget_schema")).to include(
        RDF::Statement.new(
          RDF::URI("#{base_urn}:tech:widget_schema.widget"),
          RDF::type, described_class::OWL.Class
        ),
      )
    end

    it "restricts a projection to one schema" do
      scoped = projection.graph(schema_id: "gizmo_arm")
      expect(scoped).to include(
        RDF::Statement.new(
          RDF::URI("#{base_urn}:tech:gizmo_arm.gizmo"),
          RDF::type, described_class::OWL.Class
        ),
      )
      expect(scoped).not_to include(
        RDF::Statement.new(
          RDF::URI("#{base_urn}:tech:widget_schema.widget"),
          RDF::type, described_class::OWL.Class
        ),
      )
    end

    it "resolves cross-schema attribute ranges through the corpus" do
      expect(projection.graph).to include(
        RDF::Statement.new(
          RDF::URI("#{base_urn}:tech:ap_gizmo_arm.ap_gizmo.base"),
          described_class::RDFS.range,
          RDF::URI("#{base_urn}:tech:widget_schema.widget"),
        ),
      )
    end

    it "declares the corpus ontology and imports every schema" do
      corpus = projection.graph
      ontology = RDF::URI(base_urn)
      expect(corpus).to include(
        RDF::Statement.new(ontology, RDF.type, described_class::OWL.Ontology),
      )
      projection.schema_ids.each do |id|
        expect(corpus).to include(
          RDF::Statement.new(ontology, described_class::OWL.imports,
                             RDF::URI("#{base_urn}:tech:#{id}")),
        )
      end
    end

    it "declares a schema ontology importing its interfaces" do
      scoped = projection.graph(schema_id: "ap_gizmo_arm")
      ontology = RDF::URI("#{base_urn}:tech:ap_gizmo_arm")
      expect(scoped).to include(
        RDF::Statement.new(ontology, RDF.type, described_class::OWL.Ontology),
      )
      %w[gizmo_arm widget_schema].each do |dependency|
        expect(scoped).to include(
          RDF::Statement.new(ontology, described_class::OWL.imports,
                             RDF::URI("#{base_urn}:tech:#{dependency}")),
        )
      end
    end

    it "matches the checked-in corpus Turtle snapshot" do
      golden = RDF::Graph.load(
        File.expand_path("../fixtures/ap_publication/corpus.ttl", __dir__),
        format: :turtle,
      )
      expect(triple_strings(projection.graph)).to eq(triple_strings(golden))
    end
  end

  describe "identity and reproducibility" do
    it "accepts a URN that already carries :tech or a wildcard" do
      plain = described_class.new(manifest, urn: base_urn)
      with_tech = described_class.new(manifest, urn: "#{base_urn}:tech:*")

      expect(with_tech.to_turtle).to eq(plain.to_turtle)
      expect(with_tech.to_turtle).not_to include("tech:tech")
    end

    it "serializes deterministically" do
      expect(described_class.new(manifest, urn: base_urn).to_turtle)
        .to eq(projection.to_turtle)
    end

    it "emits no blank nodes" do
      expect(projection.to_turtle).not_to include("_:")
    end
  end

  describe "#validate" do
    it "reports no structural problems" do
      expect(projection.validate).to eq([])
    end

    it "validates a single schema projection" do
      expect(projection.validate(schema_id: "example_schema")).to eq([])
    end

    it "raises for an unknown schema" do
      expect { projection.validate(schema_id: "nope") }
        .to raise_error(ArgumentError, /unknown schema/)
    end

    context "with a deliberately inconsistent corpus" do
      let(:manifest) do
        File.expand_path("../fixtures/owl/inconsistent/schemas.yaml", __dir__)
      end
      let(:base_urn) { "urn:example:owl:inconsistent:ed-1:en" }

      it "reports a superclass that is not declared in the corpus" do
        expect(projection.validate).to include(
          "superclass without class declaration: " \
          "#{base_urn}:tech:missing_parent",
        )
      end
    end
  end

  describe "golden fixture" do
    let(:golden) do
      RDF::Graph.load(
        File.expand_path("../fixtures/owl/example_schema.ttl", __dir__),
        format: :turtle,
      )
    end

    it "matches the checked-in Turtle projection" do
      expect(triple_strings(graph)).to eq(triple_strings(golden))
    end
  end
end
