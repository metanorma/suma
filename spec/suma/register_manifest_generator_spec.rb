# frozen_string_literal: true

require "spec_helper"
require "suma/register_manifest_generator"
require "tmpdir"
require "tempfile"

RSpec.describe Suma::RegisterManifestGenerator do
  let(:manifest_content) do
    {
      "schemas" => {
        "topology_schema" => { "path" => "schemas/resources/topology_schema/topology_schema.exp" },
        "action_schema" => { "path" => "schemas/resources/action_schema/action_schema.exp" },
        "aic_advanced_brep" => { "path" => "schemas/resources/aic_advanced_brep/aic_advanced_brep.exp" },
        "Activity_arm" => { "path" => "schemas/modules/activity/arm.exp" },
        "Activity_mim" => { "path" => "schemas/modules/activity/mim.exp" },
        "Activity_method_assignment_mim" => { "path" => "schemas/modules/activity_method_assignment/mim.exp" },
      },
    }
  end

  let(:manifest_file) do
    file = Tempfile.new(["schemas", ".yml"])
    file.write(YAML.dump(manifest_content))
    file.close
    file.path
  end

  let(:output_dir) { Dir.mktmpdir }

  let(:generator) do
    described_class.new(
      manifest_file,
      output_dir,
      urn: "urn:iso:std:iso:10303:-2:ed-2:en:tech:*",
      id: "iso10303-2-express",
      ref: "ISO 10303-2 EXPRESS Concepts",
    )
  end

  after do
    FileUtils.rm_rf(output_dir)
    FileUtils.rm_f(manifest_file)
  end

  describe "#generate" do
    subject(:result) { generator.generate }

    it "writes register.yaml to the output directory" do
      result
      expect(File).to exist(File.join(output_dir, "register.yaml"))
    end

    it "returns a Glossarist::DatasetRegister" do
      expect(result).to be_a(Glossarist::DatasetRegister)
    end

    it "sets the dataset identity fields" do
      expect(result.id).to eq("iso10303-2-express")
      expect(result.ref).to eq("ISO 10303-2 EXPRESS Concepts")
    end

    it "produces two top-level categories" do
      expect(result.sections.length).to eq(2)
      expect(result.sections.map(&:id)).to eq(%w[resources modules])
    end

    it "orders resources before modules" do
      expect(result.sections[0].id).to eq("resources")
      expect(result.sections[1].id).to eq("modules")
    end

    it "includes all resource schemas as children of the resources group" do
      resources = result.sections.find { |s| s.id == "resources" }
      ids = resources.children.map(&:id)
      expect(ids).to contain_exactly(
        "topology_schema", "action_schema", "aic_advanced_brep"
      )
    end

    it "includes all module schemas as children of the modules group" do
      modules_section = result.sections.find { |s| s.id == "modules" }
      ids = modules_section.children.map(&:id)
      expect(ids).to contain_exactly(
        "Activity_arm", "Activity_mim", "Activity_method_assignment_mim"
      )
    end

    it "produces human-readable section names" do
      resources = result.sections.find { |s| s.id == "resources" }
      topology = resources.children.find { |c| c.id == "topology_schema" }
      expect(topology.names["eng"]).to eq("Resource: Topology")
    end

    it "strips the wildcard from the base URN" do
      expect(result.urn).to eq("urn:iso:std:iso:10303:-2:ed-2:en:tech")
    end

    it "keeps the wildcard URN in urnAliases" do
      expect(result.urn_aliases).to include("urn:iso:std:iso:10303:-2:ed-2:en:tech:*")
    end
  end

  describe "round-trip" do
    subject(:reload) do
      generator.generate
      Glossarist::DatasetRegister.from_file(File.join(output_dir,
                                                      "register.yaml"))
    end

    it "parses back the generated YAML" do
      expect(reload).to be_a(Glossarist::DatasetRegister)
    end

    it "preserves the dataset id and ref" do
      expect(reload.id).to eq("iso10303-2-express")
      expect(reload.ref).to eq("ISO 10303-2 EXPRESS Concepts")
    end

    it "preserves the section hierarchy" do
      expect(reload.sections.length).to eq(2)
      expect(reload.sections.map(&:id)).to eq(%w[resources modules])
    end

    it "preserves child section names" do
      resources = reload.section_by_id("resources")
      topology = resources.children.find { |c| c.id == "topology_schema" }
      expect(topology.name("eng")).to eq("Resource: Topology")
    end
  end

  describe "category coverage" do
    let(:manifest_content) do
      {
        "schemas" => {
          "topology_schema" => { "path" => "schemas/resources/topology_schema/topology_schema.exp" },
          "Activity_arm" => { "path" => "schemas/modules/activity/arm.exp" },
          "core_model_foo" => { "path" => "schemas/core_model/foo/foo.exp" },
          "baz_bom" => { "path" => "schemas/bom/baz/baz_bom.exp" },
          "aic_csg" => { "path" => "schemas/aic_csg/aic_csg.exp" },
        },
      }
    end

    it "creates a separate group per category" do
      result = generator.generate
      expect(result.sections.length).to eq(5)
      expect(result.sections.map(&:id)).to eq(
        %w[resources modules business_object_models core_model other],
      )
    end

    it "maps a standalone schema to the other category" do
      result = generator.generate
      other = result.sections.find { |s| s.id == "other" }
      expect(other.children.map(&:id)).to eq(%w[aic_csg])
    end
  end

  describe "non-default language" do
    let(:generator) do
      described_class.new(
        manifest_file, output_dir,
        urn: "urn:iso:std:iso:10303:-2:ed-2:en:tech:*",
        id: "iso10303-2-express",
        ref: "ISO 10303-2 EXPRESS Concepts",
        language_code: "fra"
      )
    end

    it "writes localized section names in the requested language" do
      generator.generate
      reload = Glossarist::DatasetRegister.from_file(
        File.join(output_dir, "register.yaml"),
      )
      expect(reload.sections.first.name("fra")).to eq("Resources")
    end
  end

  describe "owner pass-through" do
    let(:generator) do
      described_class.new(
        manifest_file, output_dir,
        urn: "urn:iso:std:iso:10303:-2:ed-2:en:tech:*",
        id: "iso10303-2-express",
        ref: "ISO 10303-2 EXPRESS Concepts",
        owner: "Custom Owner"
      )
    end

    it "uses the supplied owner" do
      result = generator.generate
      expect(result.owner).to eq("Custom Owner")
    end
  end

  describe "sort order" do
    let(:manifest_content) do
      {
        "schemas" => {
          "zebra_schema" => { "path" => "schemas/resources/zebra/zebra_schema.exp" },
          "alpha_schema" => { "path" => "schemas/resources/alpha/alpha_schema.exp" },
          "Mango_schema" => { "path" => "schemas/resources/mango/mango_schema.exp" },
        },
      }
    end

    it "sorts children case-insensitively by id" do
      result = generator.generate
      children = result.sections.find { |s| s.id == "resources" }.children
      expect(children.map(&:id)).to eq(%w[alpha_schema Mango_schema
                                          zebra_schema])
    end
  end

  describe "URN handling" do
    it "strips trailing :* and keeps both forms in urnAliases (wildcard URN)" do
      result = generator.generate
      expect(result.urn).to eq("urn:iso:std:iso:10303:-2:ed-2:en:tech")
      expect(result.urn_aliases).to include("urn:iso:std:iso:10303:-2:ed-2:en:tech:*")
    end

    context "when URN has no wildcard" do
      let(:generator) do
        described_class.new(
          manifest_file, output_dir,
          urn: "urn:iso:std:iso:10303:-2:ed-2:en:tech",
          id: "iso10303-2-express",
          ref: "ISO 10303-2 EXPRESS Concepts"
        )
      end

      it "uses the URN as base and adds the wildcard alias" do
        result = generator.generate
        expect(result.urn).to eq("urn:iso:std:iso:10303:-2:ed-2:en:tech")
        expect(result.urn_aliases).to eq(
          ["urn:iso:std:iso:10303:-2:ed-2:en:tech:*"],
        )
      end
    end
  end

  describe "validation" do
    it "raises ENOENT when manifest does not exist" do
      bad = described_class.new(
        "/nonexistent/path.yml", output_dir,
        urn: "urn:iso:std:iso:10303:-2:ed-2:en:tech:*",
        id: "iso10303-2-express",
        ref: "ISO 10303-2 EXPRESS Concepts"
      )
      expect { bad.generate }.to raise_error(Errno::ENOENT)
    end

    it "raises ENOENT when manifest path is a directory" do
      bad = described_class.new(
        output_dir, output_dir,
        urn: "urn:iso:std:iso:10303:-2:ed-2:en:tech:*",
        id: "iso10303-2-express",
        ref: "ISO 10303-2 EXPRESS Concepts"
      )
      expect { bad.generate }.to raise_error(Errno::ENOENT)
    end

    it "raises ArgumentError when manifest has no schemas" do
      empty_manifest = Tempfile.new(["empty", ".yml"])
      empty_manifest.write(YAML.dump("schemas" => {}))
      empty_manifest.close
      bad = described_class.new(
        empty_manifest.path, output_dir,
        urn: "urn:iso:std:iso:10303:-2:ed-2:en:tech:*",
        id: "iso10303-2-express",
        ref: "ISO 10303-2 EXPRESS Concepts"
      )
      expect { bad.generate }.to raise_error(ArgumentError)
    ensure
      if empty_manifest && File.exist?(empty_manifest.path)
        File.unlink(empty_manifest.path)
      end
    end
  end

  describe "output directory creation" do
    let(:nested_output_dir) { File.join(output_dir, "nested", "path") }

    it "creates the output directory when it does not exist" do
      generator = described_class.new(
        manifest_file, nested_output_dir,
        urn: "urn:iso:std:iso:10303:-2:ed-2:en:tech:*",
        id: "iso10303-2-express",
        ref: "ISO 10303-2 EXPRESS Concepts"
      )
      generator.generate
      expect(File).to exist(File.join(nested_output_dir, "register.yaml"))
    end
  end
end
