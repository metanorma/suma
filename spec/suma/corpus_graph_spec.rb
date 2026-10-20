# frozen_string_literal: true

require "spec_helper"
require "suma/corpus_graph"

RSpec.describe Suma::CorpusGraph do
  subject(:graph) { described_class.from_manifest(manifest) }

  let(:manifest) do
    File.expand_path("../fixtures/closure/schemas.yaml", __dir__)
  end

  describe ".from_manifest" do
    it "indexes every schema by normalized id" do
      expect(graph.schema_ids).to contain_exactly(
        "ap_gizmo_arm", "ap_gizmo_mim", "gizmo_arm", "widget_schema",
        "broken_schema"
      )
    end
  end

  describe "#schema_exists?" do
    it "is case-insensitive" do
      expect(graph.schema_exists?("GIZMO_ARM")).to be(true)
      expect(graph.schema_exists?("no_such_schema")).to be(false)
    end
  end

  describe "#element_visible?" do
    it "sees elements declared in the same schema" do
      expect(graph.element_visible?("gizmo_arm", "gizmo")).to be(true)
      expect(graph.element_visible?("gizmo_arm", "gizmo_state")).to be(true)
    end

    it "sees elements of schemas reached through USE FROM" do
      # ap_gizmo_arm USE FROM widget_schema + gizmo_arm
      expect(graph.element_visible?("ap_gizmo_arm", "widget")).to be(true)
      expect(graph.element_visible?("ap_gizmo_arm", "calibrated_gizmo"))
        .to be(true)
    end

    it "does not see elements outside the schema and its interfaces" do
      expect(graph.element_visible?("widget_schema", "gizmo")).to be(false)
    end

    it "is false for unknown schemas" do
      expect(graph.element_visible?("nope", "widget")).to be(false)
    end
  end

  describe "#interface_targets" do
    it "lists normalized USE/REFERENCE targets" do
      expect(graph.interface_targets("ap_gizmo_mim"))
        .to contain_exactly("ap_gizmo_arm", "gizmo_arm")
    end

    it "is empty for schemas without interfaces" do
      expect(graph.interface_targets("widget_schema")).to eq([])
    end
  end

  describe "#dependency_closure" do
    it "returns the transitive interface closure" do
      expect(graph.dependency_closure("ap_gizmo_mim"))
        .to contain_exactly("ap_gizmo_arm", "gizmo_arm", "widget_schema")
    end

    it "is empty for a schema with no interfaces" do
      expect(graph.dependency_closure("widget_schema")).to eq([])
    end
  end

  describe "#dependents_of" do
    it "finds the reverse transitive closure" do
      expect(graph.dependents_of("widget_schema"))
        .to contain_exactly("ap_gizmo_arm", "ap_gizmo_mim")
    end

    it "is empty when nothing depends on the schema" do
      expect(graph.dependents_of("broken_schema")).to eq([])
    end
  end
end
