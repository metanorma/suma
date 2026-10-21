# frozen_string_literal: true

require "suma"
require "glossarist"
require "tmpdir"

# T6: the full concepts pipeline driven by a non-10303 profile — the IFC
# fixture corpus is a single standalone schema with buildingSMART-style
# Ifc-prefixed declarations, and nothing in the pipeline special-cases it.
RSpec.describe "IFC profile pipeline" do
  let(:manifest) do
    File.expand_path("../fixtures/ifc/schemas.yaml", __dir__)
  end
  let(:work_dir) { Dir.mktmpdir("suma_ifc") }
  let(:concepts_dir) { File.join(work_dir, "concepts") }
  let(:urn_base) { "urn:example:ifc" }

  after { FileUtils.rm_rf(work_dir) }

  def concept_document(concept_id)
    file = Dir[File.join(concepts_dir, "*.yaml")].find do |path|
      doc = Glossarist::V3::ConceptDocument.from_yamls(File.read(path))
      doc.concept.data.id == concept_id
    end
    Glossarist::V3::ConceptDocument.from_yamls(File.read(file))
  end

  it "extracts concepts with Ifc-prefixed entities under the ifc profile" do
    Suma::TermExtractor.new(
      manifest, concepts_dir, urn: urn_base, profile: "ifc"
    ).call

    document = concept_document("ifc4.IfcWall")
    terms = document.localizations.first.data.terms

    aggregate_failures do
      expect(document.concept.data.localized_concepts.keys).to eq(["eng"])
      expect(terms.first.designation).to eq("IfcWall")
      expect(document.localizations.first.data.definition.first.content)
        .to include("IfcRoot")
    end
  end

  it "generates a register whose sections come from the ifc profile" do
    register_dir = File.join(work_dir, "register")
    Suma::RegisterManifestGenerator.new(
      manifest, register_dir,
      urn: "#{urn_base}:tech:*",
      id: "ifc-edition",
      ref: "IFC4 Concepts",
      profile: "ifc"
    ).generate

    register = YAML.safe_load_file(File.join(register_dir, "register.yaml"))
    sections = register["sections"]
    child = sections.first["children"].first

    aggregate_failures do
      expect(sections.size).to eq(1)
      expect(sections.first["id"]).to eq("other")
      expect(sections.first.dig("names", "eng")).to eq("Other Schemas")
      expect(child["id"]).to eq("ifc4")
      expect(child.dig("names", "eng")).to eq("Schema: IFC4")
    end
  end

  it "exports schemas through the standalone category" do
    export_dir = File.join(work_dir, "schemas")
    entries = Expressir::SchemaManifest.from_file(manifest).schemas
    schemas = entries.map do |entry|
      Suma::ExpressSchema.new(
        id: entry.id, path: entry.path.to_s,
        output_path: export_dir
      )
    end
    Suma::SchemaExporter.new(
      schemas: schemas,
      output_path: export_dir,
      options: { profile: "ifc" },
    ).export

    # Standalone schemas keep their source-tree directory (structure
    # :preserve), independent of the profile.
    expect(File).to exist(File.join(export_dir, "ifc", "ifc4.exp"))
  end
end
