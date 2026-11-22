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

    # Real stand-ins for Expressir's parse result (which exposes no
    # stable public class to verify against) — no RSpec doubles, per the
    # no-doubles rule in CLAUDE.md. The plain face formats each schema
    # individually (express_schema.rb#to_plain), so the schema elements
    # carry their own format.
    let(:parsed) do
      plain_schema = Struct.new(:id) do
        def format(*)
          "PLAIN SCHEMA OUTPUT"
        end
      end
      Class.new do
        define_method(:schemas) { [plain_schema.new("widget_arm")] }

        define_method(:format) do |no_remarks: false,
                                   keep_untagged_remarks: false|
          next "PLAIN OUTPUT" if no_remarks

          keep_untagged_remarks ? "ANNOTATED+COMMENTS" : "ANNOTATED"
        end
      end.new
    end

    after { FileUtils.rm_rf(temp_dir) }

    def export(cache_dir:)
      export_schema(cache_dir: cache_dir)
    end

    def export_schema(cache_dir:)
      schema = Suma::ExpressSchema.new(
        id: "widget_arm", path: source_file, output_path: output_path,
        is_standalone_file: false
      )
      described_class.new(
        schemas: [schema], output_path: output_path,
        options: { cache_dir: cache_dir }
      ).export
      schema
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
      expect(File.read(out)).to eq("PLAIN SCHEMA OUTPUT\n")
    end

    it "parses every time when caching is disabled" do
      expect(Expressir::Express::Parser)
        .to receive(:from_file).twice.and_return(parsed)
      2.times { export(cache_dir: "") }
    end

    it "releases each schema's parsed model after its export" do
      schema = export_schema(cache_dir: "")

      # the release dropped the memoized parse: the next access re-parses
      expect(Expressir::Express::Parser)
        .to receive(:from_file).once.and_call_original
      schema.parsed
    end
  end
end
