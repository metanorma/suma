# frozen_string_literal: true

require "suma/schema_discovery"
require "suma/collection_manifest"
require "suma/collection_config"
require "tmpdir"
require "fileutils"

RSpec.describe Suma::SchemaDiscovery do
  let(:tmpdir) { Dir.mktmpdir("schema_discovery_spec") }
  let(:exp_file) do
    write("schemas/resources/test_schema/test_schema.exp", <<~EXP)
      SCHEMA test_schema;
      ENTITY foo;
      END_ENTITY;
      END_SCHEMA;
    EXP
  end
  let(:schemas_yaml_path) do
    write("schemas.yaml", <<~YAML)
      ---
      schemas:
        test_schema:
          path: #{File.expand_path(exp_file, tmpdir)}
    YAML
  end
  let(:collection_yml_path) do
    write("collection.yml", <<~YAML)
      ---
      bibdata:
        type: collection
        title:
          - type: title-main
            language: en
            content: Test Collection
        docidentifier:
          - content: ISO 12345
            type: iso
            primary: true
      manifest:
        level: collection
        title: Test Collection
        schemas-only: true
        file: #{File.expand_path(schemas_yaml_path, tmpdir)}
    YAML
  end

  after do
    FileUtils.rm_rf(tmpdir)
  end

  def write(relative_path, content)
    full = File.join(tmpdir, relative_path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
    full
  end

  describe "#load_config" do
    it "parses schemas.yaml sitting next to collection.yml into schema_config" do
      manifest = Suma::CollectionManifest.new(
        identifier: "test",
        file: collection_yml_path,
      )
      described_class.new(manifest).load_config
      expect(manifest.schema_config).to be_a(Expressir::SchemaManifest)
      expect(manifest.schema_config.schemas.map(&:id)).to include("test_schema")
    end

    it "leaves schema_config unset when the file is not collection.yml" do
      other = write("not_collection.yml", "---\nfoo: bar\n")
      manifest = Suma::CollectionManifest.new(
        identifier: "test",
        file: other,
      )
      described_class.new(manifest).load_config
      expect(manifest.schema_config).to be_nil
    end

    it "leaves schema_config unset when schemas.yaml is missing alongside" do
      write("collection.yml", <<~YAML)
        ---
        bibdata:
          type: collection
      YAML
      manifest = Suma::CollectionManifest.new(
        identifier: "test",
        file: File.expand_path("collection.yml", tmpdir),
      )
      described_class.new(manifest).load_config
      expect(manifest.schema_config).to be_nil
    end

    it "is a no-op when the manifest has no file" do
      manifest = Suma::CollectionManifest.new(identifier: "test")
      described_class.new(manifest).load_config
      expect(manifest.schema_config).to be_nil
    end
  end

  describe "#build_doc_entries" do
    it "builds one CollectionManifest per schema in schema_config" do
      manifest = Suma::CollectionManifest.new(identifier: "test")
      manifest.schema_config = Expressir::SchemaManifest.new.tap do |c|
        c.schemas << Expressir::SchemaManifestEntry.new(id: "schema_one",
                                                        path: "/tmp/schema_one.exp")
        c.schemas << Expressir::SchemaManifestEntry.new(id: "schema_two",
                                                        path: "/tmp/schema_two.exp")
      end

      entries = described_class.new(manifest).build_doc_entries("schema_docs")
      expect(entries.length).to eq(2)
      expect(entries).to all(be_an(Suma::CollectionManifest))
      expect(entries.map(&:identifier)).to contain_exactly("schema_one",
                                                           "schema_two")
    end

    it "names files as doc_<basename>.xml under schema_docs/<id>/" do
      manifest = Suma::CollectionManifest.new(identifier: "test")
      manifest.schema_config = Expressir::SchemaManifest.new.tap do |c|
        c.schemas << Expressir::SchemaManifestEntry.new(id: "action_schema",
                                                        path: "/tmp/action_schema.exp")
      end

      entry = described_class.new(manifest).build_doc_entries("schema_docs").first
      expect(entry.file).to eq("schema_docs/action_schema/doc_action_schema.xml")
    end
  end

  describe "#build_added_manifest" do
    it "wraps doc entries in a Collection whose id derives from the bibdata" do
      manifest = Suma::CollectionManifest.new(
        identifier: "parent_id",
        file: collection_yml_path,
      )
      described_class.new(manifest).load_config

      added = described_class.new(manifest).build_added_manifest("schema_docs")
      expect(added.identifier).to eq("parent_id_")
      expect(added.type).to eq("collection")
      expect(added.entry.length).to eq(1)

      doc_entry = added.entry.first
      expect(doc_entry.type).to eq("document")
      expect(doc_entry.title).to match(/\AISO\s*12345\z/)
    end
  end
end
