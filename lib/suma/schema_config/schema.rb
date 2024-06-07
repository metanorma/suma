# frozen_string_literal: true

require "shale"

module Suma
  module SchemaConfig
    class Schema < Shale::Mapper
      attribute :id, Shale::Type::String
      attribute :path, Shale::Type::String
    end
  end
end
