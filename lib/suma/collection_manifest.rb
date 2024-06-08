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

    def expand_schemas_only(path)
      if schemas_only
        doc = YAML.safe_load(File.read(file))
        schemas = YAML.safe_load(File.read(File.join(File.dirname(file), "schemas.yaml")))
        self.file = nil
        self.title = "ISO Collection"
        self.type = "collection"
        entries = schemas["schemas"].each_with_object([]) do |(k, v), m|
          fname = Pathname(v["path"]).each_filename.to_a
          fname[-1].sub!(/exp$/, "xml") # we compile these in col.compile below
          m << CollectionManifest.new(identifier: k, title: k, file: File.join(path, fname[-2], "doc_#{fname[-1]}"))
        end
        doc = Array(CollectionManifest.new(title: doc["bibdata"]["docid"]["id"], type: "document", entry: entries))
        self.entry = doc
      else
        entry&.each { |e| e.expand_schemas_only(path) }
      end
    end
  end
end
