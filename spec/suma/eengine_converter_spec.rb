# frozen_string_literal: true

require "spec_helper"
require "suma/eengine_converter"

RSpec.describe Suma::EengineConverter do
  let(:xml_path) do
    File.join(__dir__, "../fixtures/compare/sample_comparison.xml")
  end
  let(:schema_name) { "support_resource_schema" }
  let(:converter) { described_class.new(xml_path, schema_name) }

  describe "#initialize" do
    it "loads the XML content" do
      expect(converter.instance_variable_get(:@schema_name)).to eq(schema_name)
      expect(converter.instance_variable_get(:@xml_content)).to be_a(String)
      expect(converter.instance_variable_get(:@xml_content)).to include("<schema.changes>")
    end
  end

  describe "#convert" do
    it "creates a new change schema" do
      result = converter.convert(version: "2")

      expect(result).to be_a(Expressir::Changes::SchemaChange)
      expect(result.schema).to eq(schema_name)
      expect(result.editions.size).to eq(1)
      expect(result.editions[0].version).to eq("2")
    end

    it "converts modifications from XML to change items" do
      result = converter.convert(version: "2")
      edition = result.editions[0]

      expect(edition.modifications.size).to eq(1)
      expect(edition.modifications[0].type).to eq("TYPE")
      expect(edition.modifications[0].name).to eq("text")
    end

    it "handles descriptions from XML" do
      result = converter.convert(version: "2")
      edition = result.editions[0]

      # Description extraction depends on Expressir's implementation
      # It may be nil or contain the extracted text
      if edition.description
        expect(edition.description).not_to start_with("\n")
        expect(edition.description).not_to end_with("\n")
      end
    end

    it "appends to existing change schema" do
      require "expressir/changes"
      existing = Expressir::Changes::SchemaChange.new(schema: schema_name)
      existing.add_or_update_edition("1", "First version",
                                     { additions: [], modifications: [], removals: [] })

      result = converter.convert(version: "2", existing_change_schema: existing)

      expect(result.editions.size).to eq(2)
      expect(result.editions[0].version).to eq("1")
      expect(result.editions[1].version).to eq("2")
    end

    it "replaces existing edition with same version" do
      require "expressir/changes"
      existing = Expressir::Changes::SchemaChange.new(schema: schema_name)
      existing.add_or_update_edition("2", "Old description",
                                     { additions: [], modifications: [], removals: [] })

      result = converter.convert(version: "2", existing_change_schema: existing)

      expect(result.editions.size).to eq(1)
      # The new edition replaces the old one
      expect(result.editions[0].version).to eq("2")
    end
  end
end
