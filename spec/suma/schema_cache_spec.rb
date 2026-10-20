# frozen_string_literal: true

require "suma"
require "fileutils"
require "tmpdir"

RSpec.describe Suma::SchemaCache do
  let(:temp_dir) { Dir.mktmpdir }
  let(:cache_dir) { File.join(temp_dir, "cache") }
  let(:cache) { described_class.new(cache_dir) }

  after { FileUtils.rm_rf(temp_dir) }

  it "round-trips stored output" do
    cache.store("SRC", annotations: false, content: "PLAIN")
    expect(cache.fetch("SRC", annotations: false)).to eq("PLAIN")
  end

  it "misses for content never stored" do
    expect(cache.fetch("SRC", annotations: false)).to be_nil
  end

  it "invalidates when the source changes" do
    cache.store("SRC-A", annotations: false, content: "PLAIN")
    expect(cache.fetch("SRC-B", annotations: false)).to be_nil
  end

  it "keeps the plain output distinct from the annotated output" do
    cache.store("SRC", annotations: false, content: "PLAIN")
    cache.store("SRC", annotations: true, content: "ANNOTATED")
    expect(cache.fetch("SRC", annotations: false)).to eq("PLAIN")
  end

  it "keeps the annotated output distinct from the plain output" do
    cache.store("SRC", annotations: false, content: "PLAIN")
    cache.store("SRC", annotations: true, content: "ANNOTATED")
    expect(cache.fetch("SRC", annotations: true)).to eq("ANNOTATED")
  end

  it "keys on the Expressir version, so a toolchain change regenerates" do
    cache.store("SRC", annotations: false, content: "PLAIN")
    stub_const("Expressir::VERSION", "0.0.0-other")

    expect(described_class.new(cache_dir).fetch("SRC", annotations: false))
      .to be_nil
  end

  it "leaves no partial temp files behind" do
    cache.store("SRC", annotations: false, content: "PLAIN")
    expect(Dir.glob(File.join(cache_dir, "*.tmp"))).to be_empty
  end

  describe "parsed repositories" do
    let(:fixture) do
      File.expand_path("../fixtures/owl/example_schema.exp", __dir__)
    end
    let(:source) { File.read(fixture, encoding: "UTF-8") }
    let(:repository) { Expressir::Express::Parser.from_file(fixture) }

    it "round-trips a parsed repository" do
      cache.store_parsed(source, repository)
      restored = described_class.new(cache_dir).fetch_parsed(source)

      expect(restored).to be_a(Expressir::Model::ExpFile)
      schema = restored.schemas.first
      expect(schema.id).to eq("example_schema")
      expect(schema.children.map(&:id)).to include("part", "assembly")
    end

    it "misses for content never stored" do
      expect(cache.fetch_parsed("other source")).to be_nil
    end

    it "counts a miss then a hit" do
      expect(cache.fetch_parsed(source)).to be_nil
      cache.store_parsed(source, repository)
      expect(cache.fetch_parsed(source)).to be_a(
        Expressir::Model::ExpFile,
      )
      expect(cache.misses).to eq(1)
      expect(cache.hits).to eq(1)
    end

    it "keys on the Suma model version, so a suma change regenerates" do
      cache.store_parsed(source, repository)
      stub_const("Suma::VERSION", "0.0.0-other")

      expect(described_class.new(cache_dir).fetch_parsed(source)).to be_nil
    end

    it "leaves no partial temp files behind" do
      cache.store_parsed(source, repository)
      expect(Dir.glob(File.join(cache_dir, "*.tmp"))).to be_empty
    end
  end

  describe "cross-build parse reuse" do
    let(:fixture_dir) do
      File.expand_path("../fixtures/ap_publication/schemas", __dir__)
    end
    let(:paths) do
      %w[
        modules/gizmo/arm.exp
        resources/widget_schema/widget_schema.exp
      ].map { |relative| File.join(fixture_dir, relative) }
    end

    def parse_all(cache)
      paths.map do |path|
        Suma::ExpressSchema.new(
          id: nil, path: path, output_path: temp_dir, cache: cache,
        ).parsed
      end
    end

    it "parses nothing on the second build of an unchanged corpus" do
      first_cache = described_class.new(cache_dir)
      first = parse_all(first_cache)
      expect(first_cache.misses).to eq(2)

      second_cache = described_class.new(cache_dir)
      second = parse_all(second_cache)

      expect(second_cache.misses).to eq(0)
      expect(second_cache.hits).to eq(2)
      expect(second.map { |repo| repo.schemas.first.id })
        .to eq(first.map { |repo| repo.schemas.first.id })
    end
  end
end
