# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "suma/publication"

RSpec.describe Suma::Publication do
  let(:manifest) do
    File.expand_path("../fixtures/ap_publication/schemas.yaml", __dir__)
  end
  let(:output) { Dir.mktmpdir }
  let(:bundle_ids) do
    described_class.new(lead_id: lead, schema_manifest_file: manifest)
      .schemas(output_path: output).map(&:id)
  end

  after { FileUtils.remove_entry(output) }

  describe "#schemas" do
    context "with an AP lead schema" do
      let(:lead) { "ap_gizmo_mim" }

      it "returns the lead first, then the transitive closure in " \
         "breadth-first order" do
        expect(bundle_ids).to eq(
          %w[ap_gizmo_mim ap_gizmo_arm gizmo_arm widget_schema],
        )
      end

      it "builds standalone ExpressSchema instances pointed at the output" do
        schemas = described_class.new(
          lead_id: lead, schema_manifest_file: manifest,
        ).schemas(output_path: output)
        expect(schemas.first.is_standalone_file).to be(true)
        expect(schemas.first.output_path).to eq(output)
        expect(schemas.first.type).to eq(:application_protocol)
      end

      it "resolves paths relative to the manifest" do
        schemas = described_class.new(
          lead_id: lead, schema_manifest_file: manifest,
        ).schemas(output_path: output)
        expect(schemas.first.path.to_s).to end_with(
          "fixtures/ap_publication/schemas/applications/" \
          "ap_gizmo/ap_gizmo_mim.exp",
        )
      end
    end

    context "when a dependency is missing from the manifest" do
      it "raises SchemaNotFoundError naming the schema and publication" do
        app_dir = File.join(output, "schemas/applications/ap_gizmo")
        FileUtils.mkdir_p(app_dir)
        FileUtils.cp(
          File.expand_path(
            "../fixtures/ap_publication/schemas/applications/" \
            "ap_gizmo/ap_gizmo_mim.exp", __dir__
          ),
          File.join(app_dir, "ap_gizmo_mim.exp"),
        )
        broken = File.join(output, "broken.yaml")
        File.write(broken, <<~YAML)
          ---
          schemas:
            ap_gizmo_mim:
              path: schemas/applications/ap_gizmo/ap_gizmo_mim.exp
        YAML
        publication = described_class.new(
          lead_id: "ap_gizmo_mim", schema_manifest_file: broken,
        )
        expect { publication.schemas(output_path: output) }
          .to raise_error(Suma::SchemaNotFoundError,
                          /"ap_gizmo_arm".*"ap_gizmo_mim"/m)
      end
    end
  end
end
