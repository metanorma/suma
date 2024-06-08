# frozen_string_literal: true

require "shale"

module Suma
  module SchemaConfig
    class Schema < Shale::Mapper
      attribute :id, Shale::Type::String
      attribute :path, Shale::Type::String
      attribute :schemas_only, Shale::Type::Boolean
    end
  end
end
