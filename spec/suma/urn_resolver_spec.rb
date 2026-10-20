# frozen_string_literal: true

require "suma"
require "tmpdir"

RSpec.describe Suma::UrnResolver do
  subject(:resolver) do
    described_class.new(
      manifest_file: manifest,
      urn: urn_base,
      concepts_dir: concepts_dir,
      register_file: register_file,
    )
  end

  let(:manifest) do
    File.expand_path("../fixtures/ap_publication/schemas.yaml", __dir__)
  end
  let(:urn_base) { "urn:iso:std:iso:10303:-2:ed-2:en" }
  let(:concepts_dir) { Dir.mktmpdir("suma_concepts") }
  let(:register_dir) { Dir.mktmpdir("suma_register") }
  let(:register_file) { File.join(register_dir, "register.yaml") }
  let(:output_dir) { Dir.mktmpdir("suma_resolve") }

  before do
    Suma::TermExtractor.new(manifest, concepts_dir, urn: urn_base).call
    Suma::RegisterManifestGenerator.new(
      manifest, register_dir,
      urn: "#{urn_base}:tech:*",
      id: "iso10303-2-express",
      ref: "ISO 10303-2 EXPRESS Concepts"
    ).generate
  end

  after do
    [concepts_dir, register_dir, output_dir].each { |dir| FileUtils.rm_rf(dir) }
  end

  describe "#resolve" do
    it "resolves a schema URN to its declared elements and interfaces" do
      payload = resolver.resolve("#{urn_base}:tech:ap_gizmo_arm")

      expect(payload["kind"]).to eq("schema")
      expect(payload["id"]).to eq("ap_gizmo_arm")
      expect(payload["elements"]).to include("ap_gizmo")
      expect(payload["interface"]).to contain_exactly(
        "gizmo_arm", "widget_schema"
      )
    end

    it "resolves an entity URN with attributes and subtype provenance" do
      payload = resolver.resolve("#{urn_base}:tech:gizmo_arm.calibrated_gizmo")

      expect(payload["kind"]).to eq("entity")
      expect(payload["schema"]).to eq("gizmo_arm")
      expect(payload["subtype_of"]).to eq(["gizmo"])
      expect(payload["attributes"].map { |a| a["id"] })
        .to contain_exactly("calibration_factor")
      expect(payload["where_rules"]).to include("sane_factor")
      expect(payload["source"]).to eq("schemas/modules/gizmo/arm.exp")
    end

    it "resolves a type URN" do
      payload = resolver.resolve("#{urn_base}:tech:gizmo_arm.gizmo_state")

      expect(payload["kind"]).to eq("type")
      expect(payload["underlying"]).to eq("Enumeration")
    end

    it "resolves a concept URN with provenance and localizations" do
      payload = resolver.resolve("#{urn_base}:term:widget_schema.widget")

      expect(payload["kind"]).to eq("concept")
      expect(payload["uuid"]).to match(/\A[0-9a-f-]{36}\z/)
      localization = payload["localizations"].first
      expect(localization["language"]).to include("eng")
      expect(localization["terms"]).to include("widget")
      source = localization["sources"].first
      expect(source["source"])
        .to eq("#{urn_base}:tech:widget_schema")
      expect(source["sourced_from"].first)
        .to eq("#{urn_base}:tech:widget_schema.widget")
    end

    it "resolves the dataset URN with its section hierarchy" do
      payload = resolver.resolve("#{urn_base}:tech")

      expect(payload["kind"]).to eq("dataset")
      expect(payload["id"]).to eq("iso10303-2-express")
      expect(payload["sections"].map { |s| s["id"] })
        .to contain_exactly("resources", "application_protocols", "modules")
    end

    it "raises NotFoundError for an unknown URN" do
      expect { resolver.resolve("#{urn_base}:tech:nope.missing") }
        .to raise_error(described_class::NotFoundError)
    end
  end

  describe "#write" do
    it "writes JSON and HTML artifacts for every URN" do
      resolver.write(output_dir)

      resolver.artifacts.each_key do |urn|
        relative = urn.delete_prefix("urn:").split(":").join("/")
        expect(File).to exist(File.join(output_dir, "urn", "#{relative}.json"))
        expect(File).to exist(File.join(output_dir, "urn", "#{relative}.html"))
      end
    end

    it "emits canonical, parseable JSON" do
      resolver.write(output_dir)
      path = File.join(
        output_dir, "urn/iso/std/iso/10303/-2/ed-2/en/tech/gizmo_arm.gizmo.json"
      )
      payload = JSON.parse(File.read(path))

      expect(payload.keys).to eq(payload.keys.sort)
      expect(payload["urn"]).to eq("#{urn_base}:tech:gizmo_arm.gizmo")
    end

    it "writes an index linking every URN artifact" do
      resolver.write(output_dir)
      index = File.read(File.join(output_dir, "index.html"))

      resolver.artifacts.each_key do |urn|
        href = "#{urn.delete_prefix('urn:').split(':').join('/')}.html"
        expect(index).to include(href)
        expect(index).to include(urn)
      end
    end

    it "resolves every URN it emits, including register and concept URNs" do
      register = Glossarist::DatasetRegister.from_file(register_file)
      expect { resolver.resolve(register.urn) }.not_to raise_error
      expect(resolver.artifacts.keys).to all(satisfy do |urn|
        resolver.resolve(urn)
      end)
    end
  end
end
