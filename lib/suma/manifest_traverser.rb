# frozen_string_literal: true

require "expressir"

module Suma
  # Tree-walking service over a CollectionManifest.
  #
  # ManifestTraverser owns all imperative operations that walk or mutate a
  # manifest tree: finding schemas-only entries, expanding them into
  # compiled-doc sub-trees, exporting a unified Expressir::SchemaManifest,
  # and removing schemas-only sources after compilation.
  #
  # Each method takes the manifest passed at construction as its root;
  # recursion instantiates a new traverser per child node so the surface
  # stays instance-based and the data model (CollectionManifest) stays pure.
  #
  # Schema-config loading and doc-entry construction are delegated to
  # SchemaDiscovery so this class owns traversal, not schema I/O.
  class ManifestTraverser
    attr_reader :manifest

    def initialize(manifest)
      @manifest = manifest
    end

    # Returns every entry (anywhere in the tree) whose `schemas_only` flag
    # is truthy, plus +manifest+ itself if it is schemas-only.
    def find_schemas_only
      results = (manifest.entry || []).select(&:schemas_only)
      results << manifest if manifest.schemas_only
      results
    end

    # Recursively concatenate every nested schema_config into a single
    # Expressir::SchemaManifest. The manifest's own schema_config (if set)
    # seeds the result; otherwise an empty SchemaManifest is returned.
    def export_schema_config(path)
      export_config = manifest.schema_config || Expressir::SchemaManifest.new
      return export_config unless manifest.entry

      manifest.entry.each do |child|
        child_config = self.class.new(child).export_schema_config(path)
        export_config.concat(child_config) if child_config
      end

      export_config
    end

    # Expand schemas-only entries into compiled-doc sub-trees. If the
    # manifest has no file, walks children via process_entry. Otherwise
    # loads the schema_config (SchemaDiscovery), and if this entry is
    # schemas-only, hides it from the output index and appends a new
    # sub-collection that hosts the compiled docs.
    def expand_schemas_only(schema_output_path)
      return process_entry(schema_output_path) unless manifest.file

      SchemaDiscovery.new(manifest).load_config

      return process_entry(schema_output_path) unless manifest.schemas_only

      manifest.index = false

      added = SchemaDiscovery.new(manifest).build_added_manifest(schema_output_path)
      [manifest, added]
    end

    # Drop every direct child whose `schemas_only` is truthy. Called after
    # compilation so the schemas-only manifest file no longer shows up in
    # the rendered collection.
    def remove_schemas_only_sources
      return unless manifest.entry

      kept = manifest.entry.reject(&:schemas_only)
      manifest.entry = kept
    end

    private

    # Walk each child via expand_schemas_only, flattening the results back
    # into manifest.entry.
    def process_entry(schema_output_path)
      return [manifest] unless manifest.entry

      flattened = manifest.entry.each_with_object([]) do |child, acc|
        acc.concat(self.class.new(child).expand_schemas_only(schema_output_path))
      end

      manifest.entry = flattened
      [manifest]
    end
  end
end
