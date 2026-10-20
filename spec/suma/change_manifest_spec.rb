# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "expressir/changes"
require "suma/change_manifest"
require "suma/eengine_converter"

RSpec.describe Suma::ChangeManifest do
  describe ".from_schema_change" do
    context "with a real eengine conversion" do
      subject(:manifest) do
        change = Suma::EengineConverter.new(
          "support_resource_schema", File.read(xml_path)
        ).convert(version: 2)
        described_class.from_schema_change(change, version: 2)
      end

      let(:xml_path) do
        File.expand_path("../fixtures/compare/expected_comparison.xml", __dir__)
      end

      it "carries the schema and selected version" do
        expect(manifest.schema).to eq("support_resource_schema")
        expect(manifest.version).to eq(2)
      end

      it "classifies the importer's modifications as breaking" do
        by_element = manifest.entries.to_h { |e| [e.element, e] }
        expect(by_element["text"].action).to eq("modified")
        expect(by_element["text"].classification).to eq("breaking")
        expect(by_element["text"].element_type).to eq("TYPE")
        expect(by_element["document"].classification).to eq("breaking")
      end

      it "preserves the eengine descriptions" do
        text = manifest.entries.find { |e| e.element == "text" }
        expect(text.description.join).to include("Underlying Type changed")
      end
    end

    context "with additions, deletions, and mappings" do
      subject(:manifest) do
        described_class.from_schema_change(schema_change, version: 3)
      end

      let(:version_change) do
        Expressir::Changes::VersionChange.new(
          version: 3,
          additions: [
            Expressir::Changes::ItemChange.new(
              type: "ENTITY", name: "new_entity",
              description: ["ENTITY new_entity added"]
            ),
          ],
          modifications: [
            Expressir::Changes::ItemChange.new(
              type: "ATTRIBUTE", name: "widget.label",
              description: ["ATTRIBUTE widget.label type changed"]
            ),
          ],
          deletions: [
            Expressir::Changes::ItemChange.new(
              type: "ENTITY", name: "old_entity",
              description: ["ENTITY old_entity removed"]
            ),
          ],
          mappings: [
            Expressir::Changes::MappingChange.new(
              name: "ae", description: "activity entity mapping",
            ),
          ],
          changes: [],
        )
      end
      let(:schema_change) do
        Expressir::Changes::SchemaChange.new(
          schema: "gizmo_arm", versions: [version_change],
        )
      end

      it "maps each action to its taxonomy class" do
        by_element = manifest.entries.to_h { |e| [e.element, e] }
        expect(by_element["new_entity"].action).to eq("added")
        expect(by_element["new_entity"].classification).to eq("additive")
        expect(by_element["old_entity"].action).to eq("removed")
        expect(by_element["old_entity"].classification).to eq("breaking")
        expect(by_element["widget.label"].classification).to eq("breaking")
        expect(by_element["ae"].action).to eq("mapping")
        expect(by_element["ae"].classification).to eq("editorial")
        expect(by_element["ae"].element_type).to eq("MAPPING")
      end

      it "summarizes counts per classification" do
        expect(manifest.summary).to eq(
          "additive" => 1, "breaking" => 2, "editorial" => 1,
        )
      end

      it "reports breaking changes" do
        expect(manifest).to be_breaking
      end

      it "round-trips through YAML" do
        path = File.join(Dir.mktmpdir, "typed.yaml")
        File.write(path, manifest.to_yaml)
        reloaded = described_class.from_yaml(File.read(path))
        expect(reloaded.schema).to eq("gizmo_arm")
        expect(reloaded.version).to eq(3)
        expect(reloaded.entries.map(&:classification))
          .to contain_exactly("additive", "breaking", "breaking", "editorial")
      ensure
        FileUtils.rm_rf(File.dirname(path)) if path
      end

      it "renders a markdown changelog grouped by classification" do
        changelog = manifest.to_changelog
        expect(changelog).to include("## Schema `gizmo_arm` — version 3")
        expect(changelog).to include("**additive** — ENTITY `new_entity` added")
        expect(changelog)
          .to include("**breaking** — ENTITY `old_entity` removed")
        expect(changelog).to include("**editorial** — MAPPING `ae` mapping")
      end
    end
  end
end
