# frozen_string_literal: true

require "suma/collection_manifest"

RSpec.describe Suma::CollectionManifest do
  describe "data model" do
    it "round-trips identifier, title, type, and file through YAML" do
      original = described_class.new(
        identifier: "iso-123",
        title: "Sample",
        type: "document",
        file: "path/to/doc.xml",
      )

      reloaded = described_class.from_yaml(original.to_yaml)
      expect(reloaded.identifier).to eq("iso-123")
      expect(reloaded.title).to eq("Sample")
      expect(reloaded.type).to eq("document")
      expect(reloaded.file).to eq("path/to/doc.xml")
    end

    it "preserves schemas_only across YAML round-trip" do
      original = described_class.new(identifier: "iso-1", schemas_only: true)
      reloaded = described_class.from_yaml(original.to_yaml)
      expect(reloaded.schemas_only).to be(true)
    end

    it "defaults schemas_only to nil (falsy) when omitted" do
      reloaded = described_class.from_yaml(
        { "identifier" => "iso-1" }.to_yaml,
      )
      expect(reloaded.schemas_only).to be_nil.or(be(false))
    end

    it "defaults entry to an empty collection" do
      manifest = described_class.new(identifier: "root")
      expect(manifest.entry).to respond_to(:each)
      expect(manifest.entry.to_a).to eq([])
    end
  end

  describe "#schema_config" do
    it "is nil by default" do
      expect(described_class.new(identifier: "x").schema_config).to be_nil
    end

    it "can be assigned and read back" do
      manifest = described_class.new(identifier: "x")
      config = Expressir::SchemaManifest.new
      manifest.schema_config = config
      expect(manifest.schema_config).to eq(config)
    end
  end
end
