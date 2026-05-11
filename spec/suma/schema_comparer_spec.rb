# frozen_string_literal: true

require "suma/schema_comparer"
require "suma/eengine/wrapper"
require "fileutils"
require "tmpdir"

RSpec.describe Suma::SchemaComparer do
  let(:fixtures_dir) { File.expand_path("../fixtures/compare", __dir__) }
  let(:schema_v1) { File.join(fixtures_dir, "schema_v1.exp") }
  let(:schema_v2) { File.join(fixtures_dir, "schema_v2.exp") }

  describe "#compare" do
    context "input validation" do
      it "raises SchemaNotFoundError for missing trial schema" do
        allow(Suma::Eengine::Wrapper).to receive(:available?).and_return(true)
        comparer = described_class.new("nonexistent.exp", schema_v1)
        expect { comparer.compare }.to raise_error(Suma::SchemaNotFoundError)
      end

      it "raises SchemaNotFoundError for missing reference schema" do
        allow(Suma::Eengine::Wrapper).to receive(:available?).and_return(true)
        comparer = described_class.new(schema_v2, "nonexistent.exp")
        expect { comparer.compare }.to raise_error(Suma::SchemaNotFoundError)
      end

      it "raises EengineNotAvailableError when eengine is missing" do
        allow(Suma::Eengine::Wrapper).to receive(:available?).and_return(false)
        comparer = described_class.new(schema_v2, schema_v1)
        expect { comparer.compare }.to raise_error(Suma::EengineNotAvailableError)
      end
    end
  end

  describe "#extract_schema_name" do
    it "strips numeric suffixes" do
      comparer = described_class.new("/path/schema_1.exp", "/path/ref.exp")
      expect(comparer.send(:extract_schema_name, "/path/schema_1.exp")).to eq("schema")
    end

    it "preserves names without suffixes" do
      comparer = described_class.new("/path/my_schema.exp", "/path/ref.exp")
      expect(comparer.send(:extract_schema_name, "/path/my_schema.exp")).to eq("my_schema")
    end
  end

  describe "#detect_repo_root" do
    around do |ex|
      Dir.mktmpdir do |tmpdir|
        @tmpdir = tmpdir
        ex.run
      end
    end

    it "finds .git directory" do
      FileUtils.mkdir_p(File.join(@tmpdir, ".git"))
      schema = File.join(@tmpdir, "schemas", "schema.exp")
      FileUtils.mkdir_p(File.dirname(schema))
      FileUtils.touch(schema)

      comparer = described_class.new(schema, schema)
      expect(comparer.send(:detect_repo_root, schema)).to eq(@tmpdir)
    end

    it "falls back to schema directory without .git" do
      schemas_dir = File.join(@tmpdir, "schemas")
      FileUtils.mkdir_p(schemas_dir)
      schema = File.join(schemas_dir, "schema.exp")
      FileUtils.touch(schema)

      comparer = described_class.new(schema, schema)
      expect(comparer.send(:detect_repo_root, schema)).to eq(schemas_dir)
    end
  end
end
