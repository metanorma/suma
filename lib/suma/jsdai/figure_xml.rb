# frozen_string_literal: true

require "lutaml/model"

module Suma
  module Jsdai
    # Represents an image area with coordinates and href
    class FigureXmlImageArea < Lutaml::Model::Serializable
      attribute :shape, :string
      attribute :coords, :string
      attribute :href, :string

      xml do
        root "img.area"
        map_attribute "shape", to: :shape
        map_attribute "coords", to: :coords
        map_attribute "href", to: :href
      end
    end

    # Represents the img element with source and areas
    class FigureXmlImage < Lutaml::Model::Serializable
      attribute :src, :string
      attribute :areas, FigureXmlImageArea, collection: true

      xml do
        root "img"
        map_attribute "src", to: :src
        map_element "img.area", to: :areas
      end
    end

    # Represents the root imgfile.content element
    class FigureXml < Lutaml::Model::Serializable
      attribute :module, :string
      attribute :file, :string
      attribute :img, FigureXmlImage

      xml do
        root "imgfile.content"
        map_attribute "module", to: :module
        map_attribute "file", to: :file
        map_element "img", to: :img
      end
    end
  end
end
