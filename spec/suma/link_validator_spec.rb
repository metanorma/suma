# frozen_string_literal: true

require "suma/link_validator"
require "suma/schema_index"
require "expressir"
require "tmpdir"

RSpec.describe Suma::LinkValidator do
  let(:schema_path) do
    File.expand_path(
      "../fixtures/extract_terms/resources/action_schema/action_schema.exp", __dir__
    )
  end

  let(:repo) { Expressir::Express::Parser.from_file(schema_path) }
  let(:index) { Suma::SchemaIndex.new(repo) }

  let(:tmpdir) { Dir.mktmpdir("link_validator_spec") }

  after do
    FileUtils.rm_rf(tmpdir)
  end

  def write_adoc(name, body)
    path = File.join(tmpdir, name)
    File.write(path, body)
    path
  end

  describe "#validate with schema-only links" do
    it "returns no issues when every linked schema exists" do
      file = write_adoc("ok.adoc", "<<express:action_schema>>\n")
      result = described_class.new(index).validate(file => ["action_schema"])
      expect(result).to eq([])
    end

    it "reports an unresolved schema with the correct line number" do
      file = write_adoc("missing.adoc", "intro\n<<express:unknown_schema>>\n")
      result = described_class.new(index).validate(file => ["unknown_schema"])
      expect(result.length).to eq(1)
      expect(result.first.file).to eq(file)
      expect(result.first.line).to eq(2)
      expect(result.first.link).to eq("unknown_schema")
      expect(result.first.reason).to include("Schema 'unknown_schema' not found")
    end
  end

  describe "#validate with element links" do
    it "resolves entity links" do
      file = write_adoc("entity.adoc",
                        "<<express:action_schema.action_directive_relationship>>\n")
      result = described_class.new(index).validate(file => ["action_schema.action_directive_relationship"])
      expect(result).to eq([])
    end

    it "reports unresolved element when the entity is missing" do
      link = "action_schema.nonexistent_entity"
      file = write_adoc("bad_entity.adoc", "<<express:#{link}>>\n")
      result = described_class.new(index).validate(file => [link])
      expect(result.length).to eq(1)
      expect(result.first.link).to eq(link)
      expect(result.first.reason).to include("Element 'nonexistent_entity' not found")
    end

    it "reports unresolved schema before checking the element" do
      link = "missing_schema.something"
      file = write_adoc("bad_schema.adoc", "<<express:#{link}>>\n")
      result = described_class.new(index).validate(file => [link])
      expect(result.length).to eq(1)
      expect(result.first.reason).to include("Schema 'missing_schema' not found")
    end
  end

  describe "#validate with deep paths" do
    it "resolves an entity attribute reference" do
      link = "action_schema.action_directive_relationship.name"
      file = write_adoc("attr.adoc", "<<express:#{link}>>\n")
      result = described_class.new(index).validate(file => [link])
      expect(result).to eq([])
    end

    it "reports an unresolved attribute" do
      link = "action_schema.action_directive_relationship.not_an_attribute"
      file = write_adoc("bad_attr.adoc", "<<express:#{link}>>\n")
      result = described_class.new(index).validate(file => [link])
      expect(result.length).to eq(1)
      expect(result.first.reason).to include("Attribute 'not_an_attribute' not found")
    end
  end

  describe "#validate with multiple files" do
    it "accumulates unresolved results across files" do
      ok = write_adoc("ok.adoc", "<<express:action_schema>>\n")
      bad1 = write_adoc("bad1.adoc", "<<express:missing_one>>\n")
      bad2 = write_adoc("bad2.adoc", "<<express:missing_two>>\n")

      links_by_file = {
        ok => ["action_schema"],
        bad1 => ["missing_one"],
        bad2 => ["missing_two"],
      }
      result = described_class.new(index).validate(links_by_file)
      expect(result.map(&:link)).to contain_exactly("missing_one",
                                                    "missing_two")
    end

    it "uses the first occurrence line when a link appears multiple times" do
      body = "first\nsecond\n<<express:action_schema>>\nfourth\n<<express:action_schema>>\n"
      file = write_adoc("twice.adoc", body)
      result = described_class.new(index).validate(file => ["action_schema"])
      expect(result).to eq([])
    end
  end

  describe "LinkValidationResult struct" do
    it "is keyword-initialised and exposes file, line, link, reason" do
      result = Suma::LinkValidationResult.new(
        file: "f.adoc", line: 7, link: "x.y", reason: "nope",
      )
      expect(result.file).to eq("f.adoc")
      expect(result.line).to eq(7)
      expect(result.link).to eq("x.y")
      expect(result.reason).to eq("nope")
    end
  end
end
