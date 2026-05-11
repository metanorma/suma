# frozen_string_literal: true

require "suma/schema_exporter"
require "expressir"

RSpec.describe Suma::SchemaExporter do
  let(:output_dir) { Dir.mktmpdir("suma_schema_exporter_test") }

  after do
    FileUtils.rm_rf(output_dir)
  end

  describe "#export" do
    context "with standalone .exp file schemas" do
      it "exports standalone EXPRESS files to the output root" do
        standalone_schema = Struct.new(:id, :path).new(
          nil,
          File.expand_path(
            "../fixtures/extract_terms/resources/action_schema/action_schema.exp", __dir__
          ),
        )

        exporter = described_class.new(
          schemas: [standalone_schema],
          output_path: output_dir,
          options: { annotations: false },
        )

        expect { exporter.export }.not_to raise_error
        expect(Dir.glob(File.join(output_dir, "*.exp")).any?).to be true
      end
    end

    context "with manifest schemas" do
      it "exports manifest schemas to categorized subdirectories" do
        manifest_path = File.expand_path(
          "../fixtures/export/schemas-test.yml", __dir__
        )
        manifest = Expressir::SchemaManifest.from_file(manifest_path)
        manifest_schema = manifest.schemas.first

        exporter = described_class.new(
          schemas: [manifest_schema],
          output_path: output_dir,
          options: { annotations: false },
        )

        expect { exporter.export }.not_to raise_error
      end
    end
  end

  describe "type distinction" do
    it "distinguishes standalone schemas from manifest entries" do
      standalone = Struct.new(:id, :path).new("test", "/path/to/test.exp")

      manifest_path = File.expand_path(
        "../fixtures/export/schemas-test.yml", __dir__
      )
      manifest = Expressir::SchemaManifest.from_file(manifest_path)
      manifest_schema = manifest.schemas.first

      expect(standalone.is_a?(Expressir::SchemaManifestEntry)).to be false
      expect(manifest_schema.is_a?(Expressir::SchemaManifestEntry)).to be true
    end
  end
end
