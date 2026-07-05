# frozen_string_literal: true

require "suma/link_validator"
require "suma/link_validator/step"

RSpec.describe Suma::LinkValidator::Step do
  let(:context) do
    Suma::LinkValidator::Step::Context.new(
      file: "f.adoc", line: 5, link: "schema.entity.part",
      schema: schema_double, path: "schema.entity"
    )
  end

  let(:schema_double) do
    Struct.new(:id, :entities, :types, :constants, :functions, :rules,
               :procedures, :subtype_constraints).new(
                 "schema", [], [], [], [], [], [], []
               )
  end

  describe "REGISTRY" do
    it "is frozen" do
      expect(described_class::REGISTRY).to be_frozen
    end

    it "includes Entity and Type steps" do
      expect(described_class::REGISTRY).to include(described_class::Entity)
      expect(described_class::REGISTRY).to include(described_class::Type)
    end
  end

  describe ".for" do
    it "returns Entity for an Expressir Entity node" do
      entity = Expressir::Model::Declarations::Entity.new
      expect(described_class.for(entity)).to eq(described_class::Entity)
    end

    it "returns Type for an Expressir Type node" do
      type = Expressir::Model::Declarations::Type.new
      expect(described_class.for(type)).to eq(described_class::Type)
    end

    it "returns nil for an unsupported node type" do
      expect(described_class.for(Object.new)).to be_nil
    end
  end

  describe Suma::LinkValidator::Step::Entity do
    it "handles Entity nodes" do
      entity = Expressir::Model::Declarations::Entity.new
      expect(described_class.handles?(entity)).to be(true)
    end

    it "does not handle Type nodes" do
      type = Expressir::Model::Declarations::Type.new
      expect(described_class.handles?(type)).to be(false)
    end

    it "returns the matching attribute when found" do
      attribute = make_attribute("foo")
      entity = Expressir::Model::Declarations::Entity.new
      entity.attributes = [make_attribute("bar"), attribute]

      result = described_class.new.navigate(entity, "foo", context)
      expect(result).to eq(attribute)
    end

    it "matches case-insensitively" do
      attribute = make_attribute("Foo")
      entity = Expressir::Model::Declarations::Entity.new
      entity.attributes = [attribute]

      result = described_class.new.navigate(entity, "foo", context)
      expect(result).to eq(attribute)
    end

    it "returns a LinkValidationResult when the attribute is missing" do
      entity = Expressir::Model::Declarations::Entity.new

      result = described_class.new.navigate(entity, "missing", context)
      expect(result).to be_a(Suma::LinkValidationResult)
      expect(result.reason).to include("Attribute 'missing' not found")
      expect(result.file).to eq("f.adoc")
      expect(result.line).to eq(6)
      expect(result.link).to eq("schema.entity.part")
    end
  end

  describe Suma::LinkValidator::Step::Type do
    it "handles Type nodes" do
      type = Expressir::Model::Declarations::Type.new
      expect(described_class.handles?(type)).to be(true)
    end

    it "does not handle Entity nodes" do
      entity = Expressir::Model::Declarations::Entity.new
      expect(described_class.handles?(entity)).to be(false)
    end

    it "returns a failure when the type has no underlying type" do
      type = Expressir::Model::Declarations::Type.new

      result = described_class.new.navigate(type, "anything", context)
      expect(result).to be_a(Suma::LinkValidationResult)
      expect(result.reason).to include("Cannot navigate deeper from type")
    end
  end

  describe Suma::LinkValidator::Step::SchemaElementLookup do
    it "finds a named element across schema collections" do
      schema = schema_double
      entity = make_entity("my_entity")
      schema.entities = [entity]

      result = described_class.find(schema, "my_entity")
      expect(result).to eq(entity)
    end

    it "matches case-insensitively" do
      schema = schema_double
      type = make_type("My_Type")
      schema.types = [type]

      result = described_class.find(schema, "my_type")
      expect(result).to eq(type)
    end

    it "returns nil when the element is not present" do
      expect(described_class.find(schema_double, "missing")).to be_nil
    end
  end

  describe Suma::LinkValidator::Step::Context do
    it "is keyword-initialised" do
      ctx = described_class.new(
        file: "f", line: 1, link: "l", schema: nil, path: "p",
      )
      expect(ctx.file).to eq("f")
      expect(ctx.line).to eq(1)
      expect(ctx.link).to eq("l")
      expect(ctx.path).to eq("p")
    end
  end

  def make_attribute(name)
    Expressir::Model::Declarations::Attribute.new.tap do |attr|
      attr.id = name
    end
  end

  def make_entity(name)
    Expressir::Model::Declarations::Entity.new.tap do |e|
      e.id = name
    end
  end

  def make_type(name)
    Expressir::Model::Declarations::Type.new.tap do |t|
      t.id = name
    end
  end
end
