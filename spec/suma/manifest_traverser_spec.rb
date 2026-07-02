# frozen_string_literal: true

require "suma/manifest_traverser"
require "suma/collection_manifest"
require "suma/collection_config"
require "tmpdir"
require "fileutils"

RSpec.describe Suma::ManifestTraverser do
  let(:tmpdir) { Dir.mktmpdir("manifest_traverser_spec") }
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

  describe "#find_schemas_only" do
    it "returns an empty array when no entries are schemas-only" do
      plain = Suma::CollectionManifest.new(
        identifier: "plain",
        entry: [
          Suma::CollectionManifest.new(identifier: "child1"),
          Suma::CollectionManifest.new(identifier: "child2"),
        ],
      )
      expect(described_class.new(plain).find_schemas_only).to eq([])
    end

    it "collects every child marked schemas_only" do
      schemas_only_child = Suma::CollectionManifest.new(
        identifier: "so", schemas_only: true,
      )
      plain_child = Suma::CollectionManifest.new(identifier: "plain")
      root = Suma::CollectionManifest.new(
        identifier: "root",
        entry: [schemas_only_child, plain_child],
      )
      expect(described_class.new(root).find_schemas_only).to eq([schemas_only_child])
    end

    it "includes the root when the root itself is schemas_only" do
      child = Suma::CollectionManifest.new(
        identifier: "child", schemas_only: true,
      )
      root = Suma::CollectionManifest.new(
        identifier: "root", schemas_only: true, entry: [child],
      )
      expect(described_class.new(root).find_schemas_only)
        .to contain_exactly(root, child)
    end
  end

  describe "#export_schema_config" do
    it "returns the existing schema_config untouched when there are no entries" do
      existing = Expressir::SchemaManifest.new
      manifest = Suma::CollectionManifest.new(identifier: "root")
      manifest.schema_config = existing

      expect(described_class.new(manifest).export_schema_config("/anywhere"))
        .to eq(existing)
    end

    it "concats child schema_configs into the parent's when entries exist" do
      child_a = Suma::CollectionManifest.new(identifier: "a")
      child_a.schema_config = Expressir::SchemaManifest.new.tap do |c|
        c.schemas << Expressir::SchemaManifestEntry.new(id: "child_a_schema",
                                                        path: "/tmp/child_a.exp")
      end
      child_b = Suma::CollectionManifest.new(identifier: "b")
      child_b.schema_config = Expressir::SchemaManifest.new.tap do |c|
        c.schemas << Expressir::SchemaManifestEntry.new(id: "child_b_schema",
                                                        path: "/tmp/child_b.exp")
      end

      root = Suma::CollectionManifest.new(identifier: "root",
                                          entry: [
                                            child_a, child_b
                                          ])

      result = described_class.new(root).export_schema_config("/anywhere")
      expect(result.schemas.map(&:id)).to contain_exactly("child_a_schema",
                                                          "child_b_schema")
    end

    it "walks arbitrarily deep" do
      leaf = Suma::CollectionManifest.new(identifier: "leaf")
      leaf.schema_config = Expressir::SchemaManifest.new.tap do |c|
        c.schemas << Expressir::SchemaManifestEntry.new(id: "deep_schema",
                                                        path: "/tmp/deep.exp")
      end
      mid = Suma::CollectionManifest.new(identifier: "mid", entry: [leaf])
      root = Suma::CollectionManifest.new(identifier: "root", entry: [mid])

      result = described_class.new(root).export_schema_config("/anywhere")
      expect(result.schemas.map(&:id)).to eq(["deep_schema"])
    end
  end

  describe "#expand_schemas_only" do
    it "expands a schemas-only leaf into [manifest, added_manifest]" do
      manifest = Suma::CollectionManifest.new(
        identifier: "test_collection",
        file: collection_yml_path,
        schemas_only: true,
      )

      results = described_class.new(manifest).expand_schemas_only("schema_docs")
      expect(results.length).to eq(2)
      expect(results[0]).to eq(manifest)
      added = results[1]
      expect(added.identifier).to eq("test_collection_")
      expect(added.type).to eq("collection")
      expect(manifest.index).to be(false)
      expect(manifest.schema_config).to be_a(Expressir::SchemaManifest)
    end

    it "returns process_entry result when the manifest has no file" do
      child = Suma::CollectionManifest.new(identifier: "child")
      root = Suma::CollectionManifest.new(identifier: "root", entry: [child])

      results = described_class.new(root).expand_schemas_only("schema_docs")
      expect(results).to eq([root])
    end

    it "walks children when the root has entries but no file" do
      leaf1 = Suma::CollectionManifest.new(identifier: "leaf1")
      leaf2 = Suma::CollectionManifest.new(identifier: "leaf2")
      root = Suma::CollectionManifest.new(identifier: "root",
                                          entry: [
                                            leaf1, leaf2
                                          ])

      results = described_class.new(root).expand_schemas_only("schema_docs")
      expect(results).to eq([root])
      expect(root.entry.to_a).to eq([leaf1, leaf2])
    end
  end

  describe "#remove_schemas_only_sources" do
    it "drops entries whose schemas_only is truthy" do
      keep = Suma::CollectionManifest.new(identifier: "keep")
      drop = Suma::CollectionManifest.new(identifier: "drop",
                                          schemas_only: true)
      root = Suma::CollectionManifest.new(identifier: "root",
                                          entry: [
                                            keep, drop
                                          ])

      described_class.new(root).remove_schemas_only_sources

      expect(root.entry.to_a).to eq([keep])
    end

    it "leaves entries untouched when none are schemas_only" do
      a = Suma::CollectionManifest.new(identifier: "a")
      b = Suma::CollectionManifest.new(identifier: "b")
      root = Suma::CollectionManifest.new(identifier: "root", entry: [a, b])

      described_class.new(root).remove_schemas_only_sources

      expect(root.entry.to_a).to eq([a, b])
    end

    it "keeps entries whose schemas_only is explicitly false" do
      explicit = Suma::CollectionManifest.new(identifier: "explicit",
                                              schemas_only: false)
      root = Suma::CollectionManifest.new(identifier: "root", entry: [explicit])

      described_class.new(root).remove_schemas_only_sources

      expect(root.entry.to_a).to eq([explicit])
    end

    it "is a no-op when the manifest has no entry collection" do
      root = Suma::CollectionManifest.new(identifier: "root")
      expect { described_class.new(root).remove_schemas_only_sources }
        .not_to raise_error
    end
  end
end
