# frozen_string_literal: true

require "suma"
require "suma/cli/resolve"
require "tmpdir"

RSpec.describe Suma::Cli::Resolve do
  let(:manifest) do
    File.expand_path("../../fixtures/ap_publication/schemas.yaml", __dir__)
  end
  let(:urn_base) { "urn:iso:std:iso:10303:-2:ed-2:en" }
  let(:concepts_dir) { Dir.mktmpdir("suma_concepts") }
  let(:output_dir) { Dir.mktmpdir("suma_resolve_cli") }

  before do
    Suma::TermExtractor.new(manifest, concepts_dir, urn: urn_base).call
  end

  after do
    [concepts_dir, output_dir].each { |dir| FileUtils.rm_rf(dir) }
  end

  it "writes every artifact with --all" do
    described_class.start([
                            "resolve",
                            "--manifest", manifest,
                            "--urn", urn_base,
                            "--concepts", concepts_dir,
                            "--output", output_dir,
                            "--all"
                          ])

    expect(Dir[File.join(output_dir, "**/*.json")].length).to be >= 10
    expect(Dir[File.join(output_dir, "**/*.html")].length)
      .to eq(Dir[File.join(output_dir, "**/*.json")].length + 1)
    expect(File).to exist(File.join(output_dir, "index.html"))
  end

  it "writes one URN" do
    described_class.start([
                            "resolve", "#{urn_base}:tech:gizmo_arm.gizmo",
                            "--manifest", manifest,
                            "--urn", urn_base,
                            "--output", output_dir
                          ])

    path = File.join(
      output_dir, "urn/iso/std/iso/10303/-2/ed-2/en/tech/gizmo_arm.gizmo.json"
    )
    expect(File).to exist(path)
    expect(JSON.parse(File.read(path))["kind"]).to eq("entity")
  end

  it "requires a URN or --all" do
    expect do
      described_class.start([
                              "resolve",
                              "--manifest", manifest,
                              "--urn", urn_base,
                              "--output", output_dir
                            ])
    end.to raise_error(ArgumentError, /provide a URN or use --all/)
  end
end
