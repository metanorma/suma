# frozen_string_literal: true

require "spec_helper"
require "suma/register_generator"
require "tmpdir"

RSpec.describe Suma::RegisterGenerator do
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
      urn: "urn:iso:std:iso:10303:-2:ed-1:en:tech:*",
      id: "iso10303-2-express",
      ref: "ISO 10303-2 EXPRESS Concepts",
    )
  end

  after do
    FileUtils.rm_rf(output_dir)
    File.unlink(manifest_file)
  end

  describe "#generate" do
    subject(:result) { generator.generate }

    it "writes register.yaml to the output directory" do
      subject
      expect(File).to exist(File.join(output_dir, "register.yaml"))
    end

    it "returns the register data structure" do
      expect(result).to include(
        "id" => "iso10303-2-express",
        "ref" => "ISO 10303-2 EXPRESS Concepts",
      )
    end

    it "produces two top-level categories" do
      sections = result["sections"]
      expect(sections.length).to eq(2)
      expect(sections.map { |s| s["id"] }).to eq(%w[resources modules])
    end

    it "orders resources before modules" do
      sections = result["sections"]
      expect(sections[0]["id"]).to eq("resources")
      expect(sections[1]["id"]).to eq("modules")
    end

    it "includes all resource schemas as children of the resources group" do
      resources = result["sections"].find { |s| s["id"] == "resources" }
      ids = resources["children"].map { |c| c["id"] }
      expect(ids).to contain_exactly(
        "topology_schema", "action_schema", "aic_advanced_brep",
      )
    end

    it "includes all module schemas as children of the modules group" do
      modules = result["sections"].find { |s| s["id"] == "modules" }
      ids = modules["children"].map { |c| c["id"] }
      expect(ids).to contain_exactly(
        "Activity_arm", "Activity_mim", "Activity_method_assignment_mim",
      )
    end

    it "produces human-readable section names" do
      resources = result["sections"].find { |s| s["id"] == "resources" }
      topology = resources["children"].find { |c| c["id"] == "topology_schema" }
      expect(topology["names"]["eng"]).to eq("Resource: Topology")
    end

    it "strips the wildcard from the base URN" do
      expect(result["urn"]).to eq("urn:iso:std:iso:10303:-2:ed-1:en:tech")
    end

    it "keeps the wildcard URN in urnAliases" do
      expect(result["urnAliases"]).to include("urn:iso:std:iso:10303:-2:ed-1:en:tech:*")
    end
  end
end
