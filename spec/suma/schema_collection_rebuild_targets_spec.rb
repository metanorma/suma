# frozen_string_literal: true

require "suma"
require "tmpdir"

RSpec.describe Suma::SchemaCollection, "#rebuild_targets" do
  let(:manifest) do
    File.expand_path("../fixtures/ap_publication/schemas.yaml", __dir__)
  end
  let(:docs_dir) { Dir.mktmpdir }
  let(:schemas_dir) { Dir.mktmpdir }
  let(:state_file) { File.join(schemas_dir, "state.json") }

  def collection
    Suma::SchemaCollection.new(
      config_yaml: manifest,
      manifest: Suma::CollectionManifest.new,
      output_path_docs: docs_dir,
      output_path_schemas: schemas_dir,
      options: { incremental: true, state_file: state_file },
    )
  end

  def current_state
    entries = Expressir::SchemaManifest.from_file(manifest).schemas
    graph = Suma::CorpusGraph.from_manifest(manifest)
    Suma::BuildPlan.new(entries: entries, graph: graph).current_state
  end

  after do
    FileUtils.rm_rf(docs_dir)
    FileUtils.rm_rf(schemas_dir)
  end

  it "targets every schema on a first build" do
    instance = collection
    instance.finalize

    expect(instance.rebuild_targets).to contain_exactly(
      "ap_gizmo_arm", "ap_gizmo_mim", "gizmo_arm", "widget_schema"
    )
  end

  it "targets nothing when the corpus is unchanged" do
    Suma::BuildPlan.write_state(state_file, current_state)
    instance = collection
    instance.finalize

    expect(instance.rebuild_targets).to eq([])
  end

  it "targets a changed schema and its transitive dependents" do
    state = current_state.merge("widget_schema" => "stale")
    Suma::BuildPlan.write_state(state_file, state)
    instance = collection
    instance.finalize

    expect(instance.rebuild_targets).to contain_exactly(
      "widget_schema", "ap_gizmo_arm", "ap_gizmo_mim"
    )
  end
end
