# frozen_string_literal: true

require "lutaml/model"

module Suma
  module SiteConfig
    class SiteInfo < Lutaml::Model::Serializable
      attribute :organization, Lutaml::Model::Type::String
      attribute :name, Lutaml::Model::Type::String
    end

    class Sources < Lutaml::Model::Serializable
      attribute :files, Lutaml::Model::Type::String, collection: true
    end

    class Base < Lutaml::Model::Serializable
      attribute :source, Sources
      attribute :collection, SiteInfo
    end

    class Config < Lutaml::Model::Serializable
      attribute :metanorma, Base

      def self.from_file(path)
        from_yaml(File.read(path))
      end
    end
  end
end
