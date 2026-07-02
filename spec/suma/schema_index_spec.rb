# frozen_string_literal: true

require "suma/schema_index"
require "expressir"

RSpec.describe Suma::SchemaIndex do
  let(:schema_path) do
    File.expand_path(
      "../fixtures/extract_terms/resources/action_schema/action_schema.exp", __dir__
    )
  end

  let(:repo) do
    Expressir::Express::Parser.from_file(schema_path)
  end

  describe "#find_schema" do
    it "finds a schema by name (case-insensitive)" do
      index = described_class.new(repo)
      expect(index.find_schema("action_schema")).not_to be_nil
      expect(index.find_schema("ACTION_SCHEMA")).not_to be_nil
    end

    it "returns nil for unknown schema" do
      index = described_class.new(repo)
      expect(index.find_schema("nonexistent")).to be_nil
    end
  end

  describe "#find_element" do
    it "finds an entity by name (case-insensitive)" do
      index = described_class.new(repo)
      element = index.find_element("action_schema", "action")
      expect(element).not_to be_nil
      expect(element.id).to eq("action")
    end

    it "finds a type by name" do
      index = described_class.new(repo)
      element = index.find_element("action_schema", "action_method")
      expect(element).not_to be_nil
    end

    it "returns nil for unknown element" do
      index = described_class.new(repo)
      expect(index.find_element("action_schema", "nonexistent")).to be_nil
    end

    it "returns nil when schema is not found" do
      index = described_class.new(repo)
      expect(index.find_element("unknown_schema", "action")).to be_nil
    end
  end
end
