# frozen_string_literal: true

module Suma
  # Service for schema-config I/O on a single CollectionManifest node.
  #
  # SchemaDiscovery owns two concerns that previously lived on
  # CollectionManifest:
  #
  # 1. Loading the `schemas.yaml` that sits next to a `collection.yml`
  #    into the manifest's `schema_config` slot.
  # 2. Building the doc CollectionManifest sub-tree that hosts the
  #    compiled XML output for each schema in `schema_config`.
  #
  # It does not walk the manifest tree — that is ManifestTraverser's job.
  # The split keeps schema I/O in one place and tree traversal in another,
  # so each is independently testable.
  class SchemaDiscovery
    attr_reader :manifest

    def initialize(manifest)
      @manifest = manifest
    end

    # If the manifest's file is a `collection.yml` and a `schemas.yaml`
    # sits alongside it, parse it into an Expressir::SchemaManifest and
    # store it on the manifest. Otherwise leave `schema_config` untouched.
    def load_config
      return unless manifest.file
      return unless File.basename(manifest.file) == "collection.yml"

      schemas_yaml_path = File.join(File.dirname(manifest.file), "schemas.yaml")
      return unless File.exist?(schemas_yaml_path)

      manifest.schema_config = Expressir::SchemaManifest.from_file(schemas_yaml_path)
    end

    # Build a CollectionManifest sub-tree that hosts the compiled XML for
    # every schema in `manifest.schema_config`. The wrapper is named with
    # a trailing underscore so it does not collide with the parent id.
    def build_added_manifest(schema_output_path)
      doc = CollectionConfig.from_file(manifest.file)
      doc_id = doc.bibdata.id

      added = CollectionManifest.new(
        title: "Collection",
        type: "collection",
        identifier: "#{manifest.identifier}_",
      )

      added.entry = [
        CollectionManifest.new(
          title: doc_id,
          type: "document",
          entry: build_doc_entries(schema_output_path),
        ),
      ]

      added
    end

    # Build one CollectionManifest per schema in schema_config, naming
    # each output file as `doc_<basename>.xml` under
    # `<schema_output_path>/<schema_id>/`.
    def build_doc_entries(schema_output_path)
      manifest.schema_config.schemas.map do |schema|
        xml_basename = "#{File.basename(schema.path, '.exp')}.xml"
        CollectionManifest.new(
          identifier: schema.id,
          title: schema.id,
          file: File.join(schema_output_path, schema.id, "doc_#{xml_basename}"),
        )
      end
    end
  end
end
