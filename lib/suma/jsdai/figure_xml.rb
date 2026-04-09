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
        element "img.area"
        ordered
        map_attribute "shape", to: :shape, render_empty: true
        map_attribute "coords", to: :coords, render_empty: true
        map_attribute "href", to: :href, render_empty: true
      end
    end

    # Represents the img element with source and areas
    class FigureXmlImage < Lutaml::Model::Serializable
      attribute :src, :string
      attribute :areas, FigureXmlImageArea, collection: true

      xml do
        element "img"
        ordered
        map_attribute "src", to: :src, render_empty: true
        map_element "img.area", to: :areas
      end
    end

    # Represents the root imgfile.content element
    class FigureXml < Lutaml::Model::Serializable
      attribute :module, :string
      attribute :file, :string
      attribute :img, FigureXmlImage

      xml do
        element "imgfile.content"
        ordered
        map_attribute "module", to: :module, render_empty: true
        map_attribute "file", to: :file, render_empty: true
        map_element "img", to: :img
      end
    end
  end
end
