# frozen_string_literal: true

require "spec_helper"
require "suma/change_impact"
require "suma/corpus_graph"

RSpec.describe Suma::ChangeImpact do
  subject(:impact) { described_class.new(graph, manifest) }

  let(:manifest) do
    File.expand_path("../fixtures/closure/schemas.yaml", __dir__)
  end
  let(:graph) { Suma::CorpusGraph.from_manifest(manifest) }

  describe "#affected_schemas" do
    it "finds schemas that transitively depend on the changed schema" do
      expect(impact.affected_schemas("widget_schema"))
        .to contain_exactly("ap_gizmo_arm", "ap_gizmo_mim")
    end

    it "is empty for a leaf that nothing depends on" do
      expect(impact.affected_schemas("broken_schema")).to eq([])
    end
  end

  describe "#affected_publications" do
    it "flags AP publications whose closure includes the changed schema" do
      expect(impact.affected_publications("widget_schema"))
        .to contain_exactly("ap_gizmo_arm", "ap_gizmo_mim")
    end

    it "does not flag publications for an unrelated schema" do
      expect(impact.affected_publications("broken_schema")).to eq([])
    end
  end

  describe "#report" do
    it "assembles the impact report" do
      expect(impact.report("widget_schema")).to eq(
        "schema" => "widget_schema",
        "affected_schemas" => %w[ap_gizmo_arm ap_gizmo_mim],
        "affected_publications" => %w[ap_gizmo_arm ap_gizmo_mim],
      )
    end
  end
end
