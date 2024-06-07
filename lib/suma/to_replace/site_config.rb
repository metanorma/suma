# frozen_string_literal: true

require "shale"

module Suma
  module ToReplace
    module SiteConfig
      class SiteInfo < Shale::Mapper
        attribute :organization, Shale::Type::String
        attribute :name, Shale::Type::String
      end

      class Sources < Shale::Mapper
        attribute :files, Shale::Type::String, collection: true
      end

      class Base < Shale::Mapper
        attribute :source, Sources
        attribute :collection, SiteInfo
      end

      class Config < Shale::Mapper
        attribute :metanorma, Base

        def self.from_file(path)
          from_yaml(File.read(path))
        end
      end
    end
  end
end
