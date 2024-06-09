# frozen_string_literal: true

require "metanorma/cli"
require "metanorma/cli/collection"
require "metanorma/collection/collection"

module Suma
  class CollectionManifest < Metanorma::Collection::Config::Manifest
    attribute :schemas_only, Shale::Type::Boolean
    attribute :entry, CollectionManifest, collection: true
    attribute :schema_source, Shale::Type::String
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
      entry&.map do |x|
        x.export_schema_config(path)
      end.compact.each_with_object(export_config) do |x, acc|
        acc.concat(x)
        acc
      end
      export_config
    end

    def lookup(attr_sym, match)
      (entry.select do |e|
        e.send(attr_sym) == match
      end + [self.send(attr_sym) == match ? self.send(attr_sym) : nil]).compact
    end

    def expand_schemas_only(schema_output_path)
      unless file
        entry or return [self]
        ret = entry.each_with_object([]) do |e, m|
                 add = e.expand_schemas_only(schema_output_path)
                 add.each { |x| m << x }
               end
        self.entry = ret
        return [self]
      end

      if File.basename(file) == 'collection.yml'
        schemas_yaml_path = File.join(File.dirname(file), "schemas.yaml")
        if schemas_yaml_path && File.exist?(schemas_yaml_path)
          @schema_config = Suma::SchemaConfig::Config.from_file(schemas_yaml_path)
        end
      end

      unless schemas_only
        entry or return [self]
        ret = entry.each_with_object([]) do |e, m|
                 add = e.expand_schemas_only(schema_output_path)
                 add.each { |x| m << x }
               end
        self.entry = ret
        return [self]
      end

      # The schemas can't load if the file is removed
      # self.file = nil
      # If we are going to keep the schemas-only file and compile it, we can't have it showing up in output
      self.index = false
      #self.title = "Collection"
      #self.type = "collection"

      # This is the collection.yml file path
      doc = CollectionConfig.from_file(file)
      doc_id = doc.bibdata.id

      # pp @schema_config

      entries = @schema_config.schemas.map do |schema|
        # TODO: We compile these later, but where is the actual compile command?
        # Answer: in manifest_compile_adoc, on postprocess, end of initialisation of manifest object
        fname = [File.basename(schema.path, ".exp"), ".xml"].join

        CollectionManifest.new(
          identifier: schema.id,
          title: schema.id,
          file: File.join(schema_output_path, "doc_#{schema.id}", fname),
          type: "express_doc", # This means this schema is a SchemaDocument
          schema_source: schema.path
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
  end
end
