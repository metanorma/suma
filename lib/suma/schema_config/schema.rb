# frozen_string_literal: true

require "shale"

module Suma
  module SchemaConfig
    class Schema < Shale::Mapper
      attribute :id, Shale::Type::String
      attribute :path, Shale::Type::String
      # attribute :schemas_only, Shale::Type::Boolean

      # container_path is a copy of Suma::SchemaConfig::Config.path,
      # used to resolve the path of each schema within
      # Suma::SchemaConfig::Config.schemas,
      # when Suma::SchemaConfig::Config.schemas is recursively flattened
      attr_accessor :container_path
    end
  end
end
