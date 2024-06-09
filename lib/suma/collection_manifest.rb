# frozen_string_literal: true

require "metanorma/cli"
require "metanorma/cli/collection"
require "metanorma/collection/collection"

module Suma
  class CollectionManifest < Metanorma::Collection::Config::Manifest
    attribute :schemas_only, Shale::Type::Boolean
    attribute :entry, CollectionManifest, collection: true
    # attribute :schema_source, Shale::Type::String
    attr_accessor :schema_config

    yaml do
      map "identifier", to: :identifier
      map "type", to: :type
      map "level", using: { from: :level_from_yaml, to: :nop_to_yaml }
      map "title", to: :title
      map "url", to: :url
      map "attachment", to: :attachment
      map "sectionsplit", to: :sectionsplit
      map "schemas-only", to: :schemas_only
      map "index", to: :index
      map "file", to: :file
      map "fileref", using: { from: :fileref_from_yaml, to: :nop_to_yaml }
      map "entry", to: :entry
      map "docref", using: { from: :docref_from_yaml, to: :nop_to_yaml }
      map "manifest", using: { from: :docref_from_yaml, to: :nop_to_yaml }
      map "bibdata", using: { from: :bibdata_from_yaml,
                              to: :bibdata_to_yaml }
    end

    def docref_from_yaml(model, value)
      model.entry = CollectionManifest.from_yaml(value.to_yaml)
    end

    def export_schema_config(path)
      export_config = @schema_config || Suma::SchemaConfig::Config.new
      return export_config unless entry

      entry.each do |x|
        child_config = x.export_schema_config(path)
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

      # If there is collection.yml, this is a document collection, we process
      # schemas.yaml.
      if File.basename(file) == 'collection.yml'
        schemas_yaml_path = File.join(File.dirname(file), "schemas.yaml")
        if schemas_yaml_path && File.exist?(schemas_yaml_path)
          @schema_config = Suma::SchemaConfig::Config.from_file(schemas_yaml_path)
        end
      end

      return process_entry(schema_output_path) unless schemas_only

      # If we are going to keep the schemas-only file and compile it, we can't
      # have it showing up in output.
      self.index = false

      doc = CollectionConfig.from_file(file)
      doc_id = doc.bibdata.id

      entries = @schema_config.schemas.map do |schema|
        fname = [File.basename(schema.path, ".exp"), ".xml"].join

        CollectionManifest.new(
          identifier: schema.id,
          title: schema.id,
          file: File.join(schema_output_path, schema.id, "doc_#{fname}"),
          # schema_source: schema.path
        )
      end

      # we need to separate this file from the following new entries
      added = CollectionManifest.new(
        title: "Collection",
        type:  "collection",
        identifier: self.identifier + "_"
      )

      added.entry = [
        CollectionManifest.new(
          title: doc_id,
          type: "document",
          entry: entries,
        ),
      ]

      [self, added]
    end

    def remove_schemas_only_sources
      ret = entry.each_with_object([]) do |e, m|
        e.schemas_only or m << e
      end
      self.entry = ret
    end
  end
end
