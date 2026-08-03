# frozen_string_literal: true

require "suma"
require "fileutils"
require "tmpdir"

# Content-addressed caching of exported EXPRESS schema output. Caching is an
# orchestration concern driven by SchemaExporter (not the ExpressSchema data
# model): it is keyed on the schema source, so an unchanged source skips the
# Expressir parse on the next export.
RSpec.describe Suma::SchemaExporter do
  describe "schema output caching" do
    let(:temp_dir) { Dir.mktmpdir }
    let(:output_path) { File.join(temp_dir, "out") }
    let(:cache_dir) { File.join(temp_dir, "cache") }
    let(:source_file) do
      File.join(temp_dir, "modules", "widget", "arm.exp").tap do |file|
        FileUtils.mkdir_p(File.dirname(file))
        File.write(file, "SCHEMA widget_arm; END_SCHEMA;")
      end
    end

    # A real stand-in for Expressir's parse result (which exposes no stable
    # public class to verify against) — no RSpec doubles, per the no-doubles
    # rule in CLAUDE.md.
    let(:parsed) do
      Class.new do
        def to_s(no_remarks: true) = no_remarks ? "PLAIN OUTPUT" : "ANNOTATED"
        def schemas = [Struct.new(:id).new("widget_arm")]
      end.new
    end

    after { FileUtils.rm_rf(temp_dir) }

    def export(cache_dir:)
      schema = Suma::ExpressSchema.new(
        id: "widget_arm", path: source_file, output_path: output_path,
        is_standalone_file: false
      )
      described_class.new(
        schemas: [schema], output_path: output_path,
        options: { cache_dir: cache_dir }
      ).export
    end

    it "parses on a miss then reuses the cache without re-parsing" do
      expect(Expressir::Express::Parser)
        .to receive(:from_file).once.and_return(parsed)
      2.times { export(cache_dir: cache_dir) }
    end

    it "writes the cached output byte-for-byte on the cache hit" do
      out = File.join(output_path, "widget", "arm.exp")
      allow(Expressir::Express::Parser)
        .to receive(:from_file).and_return(parsed)
      2.times { export(cache_dir: cache_dir) }
      expect(File.read(out)).to eq("PLAIN OUTPUT")
    end

    it "parses every time when caching is disabled" do
      expect(Expressir::Express::Parser)
        .to receive(:from_file).twice.and_return(parsed)
      2.times { export(cache_dir: "") }
    end
  end
end
