# frozen_string_literal: true

require "suma"
require "fileutils"
require "tmpdir"

RSpec.describe Suma::ExpressSchema do
  describe "#save_exp caching" do
    let(:temp_dir) { Dir.mktmpdir }
    let(:output_path) { File.join(temp_dir, "out") }
    let(:source_file) do
      File.join(temp_dir, "modules", "widget", "arm.exp").tap do |file|
        FileUtils.mkdir_p(File.dirname(file))
        File.write(file, "SCHEMA widget_arm; END_SCHEMA;")
      end
    end

    # The native Expressir parse is stubbed so the test needs no valid EXPRESS
    # and can count parses precisely. Expressir's parse result has no stable
    # public class to verify against, hence a plain double.
    # rubocop:disable RSpec/VerifiedDoubles
    let(:parsed) do
      double("parsed", to_s: "PLAIN OUTPUT",
                       schemas: [double("schema", id: "widget_arm")])
    end
    # rubocop:enable RSpec/VerifiedDoubles

    before do
      allow(Expressir::Express::Parser)
        .to receive(:from_file).and_return(parsed)
    end

    after { FileUtils.rm_rf(temp_dir) }

    def express_schema(cache)
      described_class.new(
        id: "widget_arm", path: source_file, output_path: output_path,
        is_standalone_file: false, cache: cache
      )
    end

    it "parses on a miss then reuses the cache without re-parsing" do
      cache = Suma::SchemaCache.new(File.join(temp_dir, "cache"))

      express_schema(cache).save_exp
      express_schema(cache).save_exp

      expect(Expressir::Express::Parser).to have_received(:from_file).once
    end

    it "writes byte-identical output on the cache hit" do
      cache = Suma::SchemaCache.new(File.join(temp_dir, "cache"))
      out = File.join(output_path, "widget", "arm.exp")

      express_schema(cache).save_exp
      from_generation = File.read(out)
      express_schema(cache).save_exp

      expect(File.read(out)).to eq(from_generation)
    end

    it "parses every time when caching is disabled" do
      express_schema(Suma::NullCache.new).save_exp
      express_schema(Suma::NullCache.new).save_exp

      expect(Expressir::Express::Parser).to have_received(:from_file).twice
    end
  end
end
