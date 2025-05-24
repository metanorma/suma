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

    def self.preprocess_yaml(file)
        #yaml = YAML.safe_load(file)
        #flavor = yaml["directives"]&.detect { |x| x.is_a?(Hash) && x.has_key?("flavor") }
          #&.dig("flavor")&.upcase or return file
        #yaml["bibdata"] or return file
        #yaml["bibdata"]["ext"] ||= {}
        #yaml["bibdata"]["ext"]["flavor"] ||= flavor
        #yaml.to_yaml
      yaml
      end

    def self.from_file(path)
      from_yaml(preprocess_yaml(File.read(path)))
    end

    def to_file(path)
      File.write(path, to_yaml)
    end
  end
end
