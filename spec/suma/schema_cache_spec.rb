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

  it "keeps plain and annotated outputs distinct for one source" do
    cache.store("SRC", annotations: false, content: "PLAIN")
    cache.store("SRC", annotations: true, content: "ANNOTATED")

    expect(cache.fetch("SRC", annotations: false)).to eq("PLAIN")
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
end
