# frozen_string_literal: true

require "suma/schema_exporter"
require "suma/export_standalone_schema"
require "expressir"

RSpec.describe Suma::SchemaExporter do
  let(:output_dir) { Dir.mktmpdir("suma_schema_exporter_test") }

  after do
    FileUtils.rm_rf(output_dir)
  end

  describe "#export" do
    context "with ExportStandaloneSchema instances" do
      it "correctly identifies and handles ExportStandaloneSchema instances" do
        # This test verifies that SchemaExporter can correctly
        # identify ExportStandaloneSchema instances using is_a? check.
        standalone_schema = Suma::ExportStandaloneSchema.new(
          id: nil, # ID will be determined from parsing the file
          path: File.expand_path(
            "../fixtures/extract_terms/resources/action_schema/action_schema.exp", __dir__
          ),
        )

        exporter = described_class.new(
          schemas: [standalone_schema],
          output_path: output_dir,
          options: { annotations: false },
        )

        # Verify export completes successfully
        expect { exporter.export }.not_to raise_error

        # Verify at least one .exp file was created
        expect(Dir.glob(File.join(output_dir, "*.exp")).any?).to be true
      end
    end
  end

  describe "type checking" do
    it "correctly distinguishes ExportStandaloneSchema from manifest schemas" do
      # This test verifies the type checking mechanism works correctly
      standalone = Suma::ExportStandaloneSchema.new(
        id: "test",
        path: "/path/to/test.exp",
      )

      manifest_path = File.expand_path("../fixtures/export/schemas-test.yml",
                                       __dir__)
      manifest = Expressir::SchemaManifest.from_file(manifest_path)
      manifest_schema = manifest.schemas.first

      # Verify type checking works correctly
      expect(standalone.is_a?(Suma::ExportStandaloneSchema)).to be true
      expect(manifest_schema.is_a?(Suma::ExportStandaloneSchema)).to be false
    end
  end

  describe "integration with SchemaExporter" do
    it "handles ExportStandaloneSchema type checking correctly" do
      # This test verifies that SchemaExporter's type checking
      # for ExportStandaloneSchema works correctly.

      standalone = Suma::ExportStandaloneSchema.new(
        id: nil,
        path: File.expand_path(
          "../fixtures/extract_terms/resources/action_schema/action_schema.exp", __dir__
        ),
      )

      exporter = described_class.new(
        schemas: [standalone],
        output_path: output_dir,
        options: { annotations: false },
      )

      # The key test: SchemaExporter should correctly identify
      # the schema type and handle it appropriately
      expect { exporter.export }.not_to raise_error

      # Verify the export completed
      expect(Dir.glob(File.join(output_dir, "*.exp")).any?).to be true
    end
  end
end
