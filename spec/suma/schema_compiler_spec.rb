# frozen_string_literal: true

require "metanorma"
require "suma/schema_compiler"
require "suma/schema_template"
require "suma/express_schema"
require "stringio"
require "tmpdir"
require "fileutils"

RSpec.describe Suma::SchemaCompiler do
  let(:tmpdir) { Dir.mktmpdir("schema_compiler_spec") }
  let(:schema) do
    Suma::ExpressSchema.new(
      id: "action_schema",
      path: "/tmp/action_schema.exp",
      output_path: tmpdir,
    )
  end
  let(:template) { Suma::SchemaTemplate::Plain.new("action_schema") }
  let(:compiler) do
    described_class.new(
      schema: schema,
      output_path: tmpdir,
      template: template,
    )
  end

  after do
    FileUtils.rm_rf(tmpdir)
  end

  describe "#initialize" do
    it "exposes schema, id, output_path, and template readers" do
      expect(compiler.schema).to eq(schema)
      expect(compiler.id).to eq("action_schema")
      expect(compiler.output_path).to eq(tmpdir)
      expect(compiler.template).to eq(template)
    end
  end

  describe "#extensions" do
    it "delegates to the injected template" do
      expect(compiler.extensions).to eq("xml,html")
    end

    it "reflects the document template when injected" do
      document_compiler = described_class.new(
        schema: schema,
        output_path: tmpdir,
        template: Suma::SchemaTemplate::Document.new("action_schema"),
      )
      expect(document_compiler.extensions).to eq("xml")
    end
  end

  describe "#output_xml_path" do
    it "locates the XML output alongside the adoc filename" do
      expect(compiler.output_xml_path)
        .to eq(File.join(tmpdir, "doc_action_schema.xml"))
    end
  end

  describe "#compile" do
    let(:schema_path) do
      File.expand_path(
        "../fixtures/dummy_collection/schemas/resources/widget_schema/" \
        "widget_schema.exp", __dir__
      )
    end
    let(:schema) do
      Suma::ExpressSchema.new(
        id: "widget_schema",
        path: schema_path,
        output_path: tmpdir,
      )
    end
    let(:compiler) do
      described_class.new(
        schema: schema,
        output_path: tmpdir,
        template: Suma::SchemaTemplate::Plain.new("widget_schema"),
      )
    end

    def capture_log
      previous = Suma::Utils.output
      io = StringIO.new
      Suma::Utils.output = io
      yield
      io.string
    ensure
      Suma::Utils.output = previous
    end

    it "reuses rendered outputs when nothing it depends on changed" do
      compiler.compile

      log = capture_log { compiler.compile }

      expect(log).to include("Reusing rendered schema doc")
      expect(log).not_to include("Compiling schema (id:")
    end

    it "renders again when the schema source changes" do
      copy = File.join(tmpdir, "widget_schema.exp")
      FileUtils.cp(schema_path, copy)
      changing = described_class.new(
        schema: Suma::ExpressSchema.new(
          id: "widget_schema", path: copy, output_path: tmpdir,
        ),
        output_path: tmpdir,
        template: Suma::SchemaTemplate::Plain.new("widget_schema"),
      )
      changing.compile
      File.write(copy, "#{File.read(copy)}\n-- changed\n")

      log = capture_log { changing.compile }

      expect(log).to include("Compiling schema (id:")
    end
  end
end
