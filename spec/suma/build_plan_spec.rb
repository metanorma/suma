# frozen_string_literal: true

require "suma"
require "tmpdir"

RSpec.describe Suma::BuildPlan do
  subject(:plan) do
    described_class.new(entries: entries, graph: graph,
                        previous_state: previous_state)
  end

  let(:manifest) do
    File.expand_path("../fixtures/ap_publication/schemas.yaml", __dir__)
  end
  let(:entries) { Expressir::SchemaManifest.from_file(manifest).schemas }
  let(:graph) { Suma::CorpusGraph.from_manifest(manifest) }
  let(:previous_state) { {} }

  describe "#rebuild" do
    it "rebuilds every schema on a first build" do
      expect(plan.rebuild).to contain_exactly(
        "ap_gizmo_arm", "ap_gizmo_mim", "gizmo_arm", "widget_schema"
      )
    end

    context "when nothing changed" do
      let(:previous_state) do
        described_class.new(entries: entries, graph: graph).current_state
      end

      it "rebuilds nothing" do
        expect(plan.rebuild).to eq([])
      end
    end

    context "when a leaf resource changed" do
      let(:previous_state) do
        current = described_class.new(entries: entries, graph: graph)
          .current_state
        current.merge("widget_schema" => "stale")
      end

      it "rebuilds exactly the schema and its transitive dependents" do
        expect(plan.rebuild).to contain_exactly(
          "widget_schema", "ap_gizmo_arm", "ap_gizmo_mim"
        )
      end
    end

    context "when a module schema changed" do
      let(:previous_state) do
        current = described_class.new(entries: entries, graph: graph)
          .current_state
        current.merge("gizmo_arm" => "stale")
      end

      it "rebuilds the module, its dependents, but not unrelated schemas" do
        expect(plan.rebuild).to contain_exactly(
          "gizmo_arm", "ap_gizmo_arm", "ap_gizmo_mim"
        )
      end
    end
  end

  describe "#changed" do
    it "reports only schemas whose digest differs" do
      current = described_class.new(entries: entries, graph: graph)
        .current_state
      plan = described_class.new(
        entries: entries, graph: graph,
        previous_state: current.merge("gizmo_arm" => "stale")
      )
      expect(plan.changed).to eq(["gizmo_arm"])
    end
  end

  describe "state persistence" do
    let(:state_dir) { Dir.mktmpdir }

    after { FileUtils.rm_rf(state_dir) }

    it "round-trips the state file" do
      path = File.join(state_dir, "state.json")
      described_class.write_state(path, plan.current_state)

      expect(described_class.read_state(path)).to eq(plan.current_state)
    end

    it "treats a missing state file as empty" do
      expect(described_class.read_state(File.join(state_dir, "none.json")))
        .to eq({})
    end
  end
end
