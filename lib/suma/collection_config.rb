# frozen_string_literal: true

require_relative "utils"
require "shale"
require_relative "collection_manifest"
require "metanorma/cli"
require "metanorma/cli/collection"
require "metanorma/collection/collection"

module Suma
  class CollectionConfig < Metanorma::Collection::Config::Config
    attribute :manifest, ::Suma::CollectionManifest

    def self.from_file(path)
      from_yaml(File.read(path))
    end

    def to_file(path)
      File.open(path, "w") { |f| f.write to_yaml }
    end

    def expand_schemas_only(path)
      manifest.expand_schemas_only(path)
    end
  end
end
