# frozen_string_literal: true

require "lutaml/model"

module Suma
  module SchemaConfig
    class Schema < Lutaml::Model::Serializable
      attribute :id, Lutaml::Model::Type::String
      attribute :path, Lutaml::Model::Type::String
      # attribute :schemas_only, Lutaml::Model::Type::Boolean

      # container_path is a copy of Suma::SchemaConfig::Config.path,
      # used to resolve the path of each schema within
      # Suma::SchemaConfig::Config.schemas,
      # when Suma::SchemaConfig::Config.schemas is recursively flattened
      attr_accessor :container_path
    end
  end
end
