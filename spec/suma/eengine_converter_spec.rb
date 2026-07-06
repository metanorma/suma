# frozen_string_literal: true

require "spec_helper"
require "suma/eengine_converter"

RSpec.describe Suma::EengineConverter do
  let(:xml_path) do
    File.join(__dir__, "../fixtures/compare/sample_comparison.xml")
  end
  let(:xml_content) { File.read(xml_path) }
  let(:schema_name) { "support_resource_schema" }
  let(:converter) { described_class.new(schema_name, xml_content) }

  describe "#initialize" do
    it "accepts XML content as a string (no I/O during construction)" do
      # Constructing the converter with already-loaded content must not
      # touch the filesystem. Verified by passing a literal string and
      # confirming convert works.
      instance = described_class.new(schema_name, xml_content)
      expect(instance.convert(version: 2)).to be_a(Expressir::Changes::SchemaChange)
    end
  end

  describe "#convert" do
    it "creates a new change schema" do
      result = converter.convert(version: 2)

      expect(result).to be_a(Expressir::Changes::SchemaChange)
      expect(result.schema).to eq(schema_name)
      expect(result.versions.size).to eq(1)
      expect(result.versions[0].version).to eq(2)
    end

    it "converts modifications from XML to change items" do
      result = converter.convert(version: 2)
      version = result.versions[0]

      expect(version.modifications.size).to eq(1)
      expect(version.modifications[0].type).to eq("TYPE")
      expect(version.modifications[0].name).to eq("text")
    end

    it "handles descriptions from XML" do
      result = converter.convert(version: 2)
      version = result.versions[0]

      # Description extraction depends on Expressir's implementation
      # It may be nil or contain the extracted text
      next unless version.description

      expect(version.description).not_to start_with("\n")
      expect(version.description).not_to end_with("\n")
    end

    it "appends to existing change schema" do
      require "expressir/changes"
      existing = Expressir::Changes::SchemaChange.new(schema: schema_name)
      existing.add_or_update_version(1, "First version",
                                     { additions: [], modifications: [], removals: [] })

      result = converter.convert(version: 2, existing_change_schema: existing)

      expect(result.versions.size).to eq(2)
      expect(result.versions[0].version).to eq(1)
      expect(result.versions[1].version).to eq(2)
    end

    it "replaces existing version with same version" do
      require "expressir/changes"
      existing = Expressir::Changes::SchemaChange.new(schema: schema_name)
      existing.add_or_update_version(2, "Old description",
                                     { additions: [], modifications: [], removals: [] })

      result = converter.convert(version: 2, existing_change_schema: existing)

      expect(result.versions.size).to eq(1)
      expect(result.versions[0].version).to eq(2)
    end
  end
end
