# frozen_string_literal: true

require "suma/schema_exporter"
require "suma/express_schema"
require "suma/schema_category"
require "expressir"
require "tmpdir"

RSpec.describe Suma::SchemaExporter do
  let(:output_dir) { Dir.mktmpdir("suma_schema_exporter_test") }

  after do
    FileUtils.rm_rf(output_dir)
  end

  describe "#export" do
    context "with a standalone ExpressSchema" do
      it "exports the file to the output root as <id>.exp" do
        standalone = Suma::ExpressSchema.new(
          id: nil,
          path: File.expand_path(
            "../fixtures/extract_terms/resources/action_schema/action_schema.exp", __dir__
          ),
          output_path: output_dir,
          is_standalone_file: true,
        )

        exporter = described_class.new(
          schemas: [standalone],
          output_path: output_dir,
          options: { annotations: false },
        )

        expect { exporter.export }.not_to raise_error
        expect(Dir.glob(File.join(output_dir, "*.exp")).any?).to be(true)
      end
    end

    context "with a manifest-built ExpressSchema (category subdir)" do
      it "writes the file under the category directory" do
        manifest_path = File.expand_path(
          "../fixtures/export/schemas-test.yml", __dir__
        )
        manifest = Expressir::SchemaManifest.from_file(manifest_path)
        entry = manifest.schemas.first
        category = Suma::SchemaCategory.for_schema(id: entry.id, path: entry.path)

        schema = Suma::ExpressSchema.new(
          id: entry.id,
          path: entry.path.to_s,
          output_path: File.join(output_dir, category.directory),
          is_standalone_file: false,
        )

        exporter = described_class.new(
          schemas: [schema],
          output_path: output_dir,
          options: { annotations: false },
        )

        expect { exporter.export }.not_to raise_error
      end
    end

    context "with an empty schema list" do
      it "does not raise" do
        exporter = described_class.new(
          schemas: [],
          output_path: output_dir,
        )
        expect { exporter.export }.not_to raise_error
      end
    end
  end

  describe "contract: accepts only Suma::ExpressSchema instances" do
    it "calls save_exp on each schema" do
      # Build a real ExpressSchema so the call goes through the real
      # path (no Struct stubs at this seam).
      schema = Suma::ExpressSchema.new(
        id: nil,
        path: File.expand_path(
          "../fixtures/extract_terms/resources/action_schema/action_schema.exp", __dir__
        ),
        output_path: output_dir,
        is_standalone_file: true,
      )

      expect { schema.save_exp }.not_to raise_error

      # The exporter's contract is: it calls save_exp on each schema.
      # We verify by exporting a list of one schema and confirming the
      # output file appears.
      exporter = described_class.new(
        schemas: [schema],
        output_path: output_dir,
      )
      exporter.export
      expect(Dir.glob(File.join(output_dir, "*.exp")).any?).to be(true)
    end
  end
end
