# frozen_string_literal: true

require "json"
require "pathname"
require "tmpdir"

RSpec.describe Suma::Delivery::Plan do
  around do |example|
    Dir.mktmpdir do |dir|
      @repo = Pathname.new(dir)
      write_fixture
      example.run
    end
  end

  let(:out_path) { @repo / "build" / "plan.json" }
  let(:plan) do
    described_class.new(repo_root: @repo, out: out_path).generate
  end

  def write_fixture
    (@repo / "documents" / "iso-10303-41").mkpath
    (@repo / "documents" / "iso-10303-41" / "sections").mkpath
    (@repo / "schemas" / "resources").mkpath
    write_collection_manifest
    write_part_collection
    write_part_inputs
    write_schema
  end

  def write_schema
    File.write(@repo / "schemas" / "resources" / "fundamentals.exp",
               "schema fundamentals 'x';\nEND_SCHEMA;\n")
  end

  def write_collection_manifest
    File.write(@repo / "collection-resources.yml", <<~YAML)
      manifest:
        docref:
        - file: documents/iso-10303-41/collection.yml
        - file: documents/missing-part/collection.yml
    YAML
  end

  def write_part_collection
    File.write(@repo / "documents" / "iso-10303-41" / "collection.yml", <<~YAML)
      bibdata:
        docid:
          id: ISO 10303-41
        copyright:
          from: 2026
      manifest:
        docref:
        - fileref: ../../plain_schemas/resources/fundamentals.exp
          identifier: fundamentals
    YAML
  end

  def write_part_inputs
    dir = @repo / "documents" / "iso-10303-41"
    File.write(dir / "document.adoc", ":copyright-year: 2025\n")
    File.write(dir / "sections" / "intro.adoc", "== Intro\n")
  end

  def reload
    JSON.parse(File.read(out_path))
  end

  it "writes one part per docref, skipping missing ones" do
    expect(plan["parts_count"]).to eq(1)
    expect(plan["parts"].size).to eq(1)
  end

  it "records the plan header fields" do
    expect(plan["version"]).to eq(1)
    expect(plan["source_collection"]).to eq("collection-resources.yml")
    expect(plan["build_commit"]).to be_a(String)
    expect(plan["build_commit"]).not_to be_empty
    expect(plan["build_timestamp"]).to match(/\A\d{4}-\d{2}-\d{2}T/)
  end

  it "derives identity from bibdata, falling back to the directory name" do
    part = plan["parts"].first
    expect(part["part_dir"]).to eq("iso-10303-41")
    expect(part["source_dir"]).to eq("documents/iso-10303-41")
    expect(part["doc_id"]).to eq("ISO 10303-41")
    # :copyright-year: in document.adoc wins over bibdata copyright year
    expect(part["year"]).to eq("2025")
    expect(part["iso_name"]).to eq("ISO_ISO 10303-41_2025")
  end

  it "resolves plain_schemas filerefs to their schemas/ source" do
    part = plan["parts"].first
    expect(part["exp_files"]).to eq(["schemas/resources/fundamentals.exp"])
    expect(part["deps_hash"]).to start_with("sha256:")
  end

  it "inventories the part's inputs" do
    part = plan["parts"].first
    expect(part["input_files"]).to contain_exactly(
      "documents/iso-10303-41/collection.yml",
      "documents/iso-10303-41/document.adoc",
      "documents/iso-10303-41/sections/intro.adoc",
      "schemas/resources/fundamentals.exp",
    )
    expect(part["doc_hash"]).to start_with("sha256:")
  end

  it "produces stable hashes for stable inputs" do
    first = plan["parts"].first["doc_hash"]
    File.write(@repo / "documents" / "iso-10303-41" / "sections" / "intro.adoc",
               "== Intro v2\n")
    second = described_class.new(repo_root: @repo, out: out_path)
      .generate["parts"].first["doc_hash"]
    expect(first).not_to eq(second)
  end

  it "falls back to the directory name when bibdata has no docid" do
    coll = @repo / "documents" / "iso-10303-41" / "collection.yml"
    File.write(coll, "bibdata: {}\n")
    expect(plan["parts"].first["doc_id"]).to eq("10303-41")
  end
end
