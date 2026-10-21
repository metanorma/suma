# frozen_string_literal: true

require "suma"
require "zip"
require "tmpdir"

RSpec.describe Suma::GcrPackage do
  let(:manifest) do
    File.expand_path("../fixtures/owl/schemas.yaml", __dir__)
  end
  let(:urn_base) { "urn:example:gcr:example:ed-1:en" }
  let(:work_dir) { Dir.mktmpdir("suma_gcr") }
  let(:concepts_dir) { File.join(work_dir, "concepts") }
  let(:register_dir) { File.join(work_dir, "register") }
  let(:register_file) { File.join(register_dir, "register.yaml") }
  let(:output_dir) { File.join(work_dir, "out") }

  before do
    FileUtils.mkdir_p(concepts_dir)
    Suma::TermExtractor.new(manifest, concepts_dir, urn: urn_base).call
    Suma::RegisterManifestGenerator.new(
      manifest, register_dir,
      urn: "#{urn_base}:tech:*",
      id: "example-express",
      ref: "Example EXPRESS Concepts"
    ).generate
  end

  after { FileUtils.rm_rf(work_dir) }

  def package(created_at: Time.utc(2026, 1, 1))
    described_class.new(
      concepts_dir: concepts_dir,
      register_file: register_file,
      shortname: "example-express",
      version: "1.0.0",
      title: "Example EXPRESS Concepts",
      description: "Concepts extracted from the example corpus",
      created_at: created_at,
    )
  end

  def archive_entries(path)
    entries = {}
    Zip::File.open(path) do |zip|
      zip.each do |entry|
        next if entry.directory?

        entries[entry.name] = entry.get_input_stream.read
      end
    end
    entries
  end

  describe "#write" do
    subject(:paths) { package.write(output_dir) }

    it "writes the versioned and unversioned archives" do
      expect(paths.map { |p| File.basename(p) }).to contain_exactly(
        "example-express-1.0.0.gcr", "example-express.gcr"
      )
      expect(File).to exist(paths.first)
    end

    it "packages metadata, register, and every concept" do
      entries = archive_entries(paths.first)

      expect(entries.keys).to include(
        "metadata.yaml", "register.yaml", "concepts/example_schema.part.yaml"
      )
      metadata = YAML.safe_load(entries["metadata.yaml"])
      expect(metadata["shortname"]).to eq("example-express")
      expect(metadata["version"]).to eq("1.0.0")
      expect(metadata["created_at"]).to eq("2026-01-01T00:00:00Z")
      expect(metadata["uri"]).to eq("#{urn_base}:tech")
      expect(metadata["uri_aliases"]).to eq(["#{urn_base}:tech:*"])
      expect(metadata["statistics"]["total_concepts"]).to eq(4)
      expect(metadata["statistics"]["languages"]).to eq(["eng"])
      expect(metadata["schema_version"]).to eq("1.0.0")
    end

    it "emits the canonical concept format" do
      entries = archive_entries(paths.first)
      concept = YAML.safe_load(entries["concepts/example_schema.part.yaml"])

      expect(concept["termid"]).to eq("example_schema.part")
      expect(concept["term"]).to eq("part")
      expect(concept["eng"]["terms"].first).to include(
        "type" => "expression",
        "designation" => "part",
        "normative_status" => "preferred",
      )
      expect(concept["eng"]["definition"]).to be_an(Array)
      expect(concept["eng"]["definition"].first["content"])
        .to include("entity data type")
      source = concept["eng"]["sources"].first
      expect(source["type"]).to eq("authoritative")
      expect(source["origin"]["ref"]["source"])
        .to eq("#{urn_base}:tech:example_schema")
    end

    it "is byte-reproducible with a pinned timestamp" do
      first = package(created_at: Time.utc(2026, 1, 1)).write(output_dir)
      second_dir = File.join(work_dir, "out2")
      second = package(created_at: Time.utc(2026, 1, 1)).write(second_dir)

      expect(File.binread(first.first)).to eq(File.binread(second.first))
    end
  end

  describe "validation" do
    it "rejects packages with duplicate termids" do
      # The extractor cannot produce duplicates; simulate by pointing the
      # package at a directory containing the same concept twice.
      dup_dir = File.join(work_dir, "dup")
      FileUtils.mkdir_p(dup_dir)
      source = Dir[File.join(concepts_dir, "*.yaml")].first
      content = File.read(source)
      File.write(File.join(dup_dir, "a.yaml"), content)
      File.write(File.join(dup_dir, "b.yaml"), content)

      duplicating = described_class.new(
        concepts_dir: dup_dir,
        register_file: register_file,
        shortname: "example-express",
        version: "1.0.0",
        title: "T",
        description: "D",
      )
      expect { duplicating.write(output_dir) }
        .to raise_error(Suma::Error, /duplicate termid/)
    end
  end
end
