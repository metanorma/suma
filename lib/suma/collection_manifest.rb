# frozen_string_literal: true

require "metanorma"
require "expressir"

module Suma
  # Pure data model for one node of a Metanorma collection manifest.
  #
  # CollectionManifest extends the Metanorma config manifest to add the
  # `schemas_only` flag and an `entry` sub-collection. It owns only state:
  # attributes, YAML mappings, and the `schema_config` slot populated by
  # SchemaDiscovery. Tree-walking logic lives in ManifestTraverser; schema
  # I/O lives in SchemaDiscovery.
  class CollectionManifest < Metanorma::Collection::Config::Manifest
    attribute :schemas_only, Lutaml::Model::Type::Boolean
    attribute :entry, CollectionManifest, collection: true,
                                          initialize_empty: true
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
  end
end
