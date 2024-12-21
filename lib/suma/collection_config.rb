# frozen_string_literal: true

require_relative "utils"
require "lutaml/model"
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
  end
end
