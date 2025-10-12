# frozen_string_literal: true

require "metanorma/cli"
require "metanorma/cli/collection"
require "metanorma/collection/collection"
require "expressir"

module Suma
  class CollectionManifest < Metanorma::Collection::Config::Manifest
    attribute :schemas_only, Lutaml::Model::Type::Boolean
    attribute :entry, CollectionManifest, collection: true,
                                          initialize_empty: true
    # attribute :schema_source, Lutaml::Model::Type::String
    attr_accessor :schema_config

    yaml do
      map "identifier", to: :identifier
      map "type", to: :type
      map "level", with: { from: :level_from_yaml, to: :nop_to_yaml }
      map "title", to: :title
      map "url", to: :url
      map "attachment", to: :attachment
      map "sectionsplit", to: :sectionsplit
      map "schemas-only", to: :schemas_only
      map "index", to: :index
      map "file", to: :file
      map "fileref", with: { from: :fileref_from_yaml, to: :nop_to_yaml }
      map "entry", to: :entry
      map "docref", with: { from: :docref_from_yaml, to: :nop_to_yaml }
      map "manifest", with: { from: :docref_from_yaml, to: :nop_to_yaml }
      map "bibdata", with: { from: :bibdata_from_yaml,
                             to: :bibdata_to_yaml }
    end

    def docref_from_yaml(model, value)
      model.entry = CollectionManifest.from_yaml(value.to_yaml)
    end

    # Recursively exports schema configuration by traversing collection manifests.
    #
    # This method builds an EXPRESS Schema Manifest (Expressir::SchemaManifest) by:
    # 1. Starting with an empty or existing Expressir::SchemaManifest
    # 2. Recursively traversing child entries to collect schemas
    # 3. Using Expressir::SchemaManifest#concat to combine manifests
    #
    # The actual schema manifest operations (creation, concatenation, serialization)
    # are handled by Expressir's SchemaManifest class, keeping the logic DRY.
    #
    # @param path [String] Base path for resolving relative schema paths
    # @return [Expressir::SchemaManifest] Combined schema manifest
    def export_schema_config(path)
      export_config = @schema_config || Expressir::SchemaManifest.new
      return export_config unless entry

      entry.each do |x|
        child_config = x.export_schema_config(path)
        # Use Expressir's concat method to combine schema manifests
        export_config.concat(child_config) if child_config
      end

      export_config
    end

    def lookup(attr_sym, match)
      results = entry.select { |e| e.send(attr_sym) == match }
      results << self if send(attr_sym) == match
      results
    end

    def process_entry(schema_output_path)
      return [self] unless entry

      ret = entry.each_with_object([]) do |e, m|
        add = e.expand_schemas_only(schema_output_path)
        m.concat(add)
      end

      self.entry = ret
      [self]
    end

    def expand_schemas_only(schema_output_path)
      return process_entry(schema_output_path) unless file

      update_schema_config

      return process_entry(schema_output_path) unless schemas_only

      # If we are going to keep the schemas-only file and compile it, we can't
      # have it showing up in output.
      self.index = false

      [self, added_collection_manifest]
    end

    def remove_schemas_only_sources
      ret = entry.each_with_object([]) do |e, m|
        e.schemas_only or m << e
      end
      self.entry = ret
    end

    def entries(schema_output_path)
      @schema_config.schemas.map do |schema|
        fname = [File.basename(schema.path, ".exp"), ".xml"].join

        CollectionManifest.new(
          identifier: schema.id,
          title: schema.id,
          file: File.join(schema_output_path, schema.id, "doc_#{fname}"),
          # schema_source: schema.path
        )
      end
    end

    def added_collection_manifest
      doc = CollectionConfig.from_file(file)
      doc_id = doc.bibdata.id

      # we need to separate this file from the following new entries
      added = CollectionManifest.new(
        title: "Collection",
        type: "collection",
        identifier: "#{identifier}_",
      )

      added.entry = [
        CollectionManifest.new(
          title: doc_id,
          type: "document",
          entry: entries,
        ),
      ]

      added
    end

    def update_schema_config
      # If there is collection.yml, this is a document collection, we process
      # schemas.yaml.
      if File.basename(file) == "collection.yml"
        schemas_yaml_path = File.join(File.dirname(file), "schemas.yaml")
        if schemas_yaml_path && File.exist?(schemas_yaml_path)
          @schema_config = Expressir::SchemaManifest.from_file(schemas_yaml_path)
        end
      end
    end
  end
end
