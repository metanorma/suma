# frozen_string_literal: true

require "metanorma/cli"
require "metanorma/cli/collection"
require "metanorma/collection/collection"

module Suma
  class CollectionManifest < Metanorma::Collection::Config::Manifest
    attribute :schemas_only, Shale::Type::Boolean
    attribute :entry, CollectionManifest, collection: true

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

    def is_express_doc
      type == "express_doc"
    end

    def all_express_docs
      entry&.map(&:all_express_docs)&.flatten&.compact&.+ (is_express_doc ? [self] : [])
    end

    attr_accessor :schema_xml_files

    def expand_schemas_only(schema_output_path)
      unless schemas_only
        return entry&.each do |e|
                 e.expand_schemas_only(schema_output_path)
               end
      end

      # This is the collection.yml file path
      # doc = YAML.safe_load(File.read(file))
      doc = CollectionConfig.from_file(file)
      doc_id = doc.bibdata.id

      # This is the schemas.yml file path
      schemas_yaml_path = File.join(File.dirname(file), "schemas.yaml")
      schema_config = SchemaConfig::Config.from_file(schemas_yaml_path)

      # The schemas can't load if the file is removed
      # self.file = nil
      self.title = "Collection"
      self.type = "collection"

      entries = schema_config.schemas.map do |schema|
        # TODO: We compile these later, but where is the actual compile command?
        fname = [File.basename(schema.path, ".exp"), ".xml"].join
        CollectionManifest.new(
          identifier: schema.id,
          title: schema.id,
          file: File.join(schema_output_path, "doc_#{schema.id}", fname),
          type: "express_doc" # This means this schema is a SchemaDocument
        )
      end

      self.entry = [
        CollectionManifest.new(
          title: doc_id,
          type: "document",
          entry: entries
        )
      ]
    end
  end
end
