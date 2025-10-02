# frozen_string_literal: true

require "lutaml/model"
require_relative "figure_xml"
require_relative "figure_image"

# Configure XML adapter
Lutaml::Model::Config.configure do |config|
  config.xml_adapter_type = :nokogiri
end

module Suma
  module Jsdai
    # Main class for JSDAI figure conversion
    class Figure
      attr_reader :xml, :image

      def initialize(xml_file, image_file)
        @xml = FigureXml.from_xml(File.read(xml_file))
        @image = FigureImage.new(image_file)
        @xml_file = xml_file
      end

      def to_svg
        width, height = @image.dimensions
        svg_parts = []

        svg_parts << '<?xml version="1.0" encoding="UTF-8"?>'
        svg_parts << '<svg xmlns="http://www.w3.org/2000/svg" '
        svg_parts << 'xml:space="preserve" '
        svg_parts << 'style="enable-background:new 0 0 595.28 841.89;" '
        svg_parts << "height=\"#{height}\" "
        svg_parts << "width=\"#{width}\" "
        svg_parts << "viewBox=\"0 0 #{width} #{height}\" "
        svg_parts << 'y="0px" x="0px" id="Layer_1" version="1.1">'
        svg_parts << "\n\t\t\t\n\t\t\t"

        # Add embedded image
        svg_parts << "<image href=\"#{@image.to_base64}\" "
        svg_parts << "height=\"#{height}\" "
        svg_parts << "width=\"#{width}\" "
        svg_parts << 'style="overflow:visible;">'
        svg_parts << "\n\t\t\t</image>\n\t\t\t"

        # Add clickable areas
        area_parts = @xml.img.areas.each_with_index.map do |area, index|
          coords = parse_coords(area.coords)
          rect_attrs = []
          rect_attrs << 'onmouseout="this.style.opacity=0" '
          rect_attrs << 'onmouseover="this.style.opacity=1" '
          rect_attrs << 'style="opacity: 0; fill: rgb(33, 128, 255); '
          rect_attrs << "fill-opacity: 0.3; stroke: rgb(0, 128, 255); "
          rect_attrs << 'stroke-width: 1px; stroke-linecap: butt; '
          rect_attrs << 'stroke-linejoin: miter; stroke-opacity: 1;" '
          rect_attrs << "height=\"#{coords[:height]}\" "
          rect_attrs << "width=\"#{coords[:width]}\" "
          rect_attrs << "y=\"#{coords[:y]}\" "
          rect_attrs << "x=\"#{coords[:x]}\"/>"

          "<a href=\"#{index + 1}\"><rect #{rect_attrs.join}</a>"
        end

        svg_parts << area_parts.join
        svg_parts << "\n\t\t</svg>"
        svg_parts.join
      end

      def to_exp
        basename = File.basename(@xml_file, ".xml")
        schema_name = extract_schema_name(basename)
        anchor_id = basename.sub(/expg/, "_expg")

        exp_parts = []
        exp_parts << "(*\"#{schema_name}.__expressg\""
        exp_parts << "\n[[#{anchor_id}]]"
        exp_parts << "\n[.svgmap]"
        exp_parts << "\n===="
        exp_parts << "\nimage::#{basename}.svg[]"
        exp_parts << "\n"

        @xml.img.areas.each_with_index do |area, index|
          target = extract_target_from_href(area.href)
          exp_parts << "\n* <<#{target}>>; #{index + 1}"
        end

        exp_parts << "\n===="
        exp_parts << "\n*)\n"
        exp_parts.join
      end

      private

      def parse_coords(coords_str)
        parts = coords_str.split(",").map(&:to_i)
        {
          x: parts[0],
          y: parts[1],
          width: parts[2] - parts[0],
          height: parts[3] - parts[1],
        }
      end

      def extract_schema_name(basename)
        # Extract schema name from basename like "action_schemaexpg2"
        # Result should be "action_schema"
        basename.sub(/expg\d+$/, "")
      end

      def extract_target_from_href(href)
        # Extract the target from href like
        # "../../resources/action_schema/action_schema.xml#action_schema.as_name_attribute_select"
        # Result should be "express:action_schema.as_name_attribute_select"
        #
        # Or from href like "../../resources/basic_attribute_schema/basic_attribute_schema.xml"
        # Result should be "express:basic_attribute_schema"
        if href =~ /#(.+)$/
          "express:#{::Regexp.last_match(1)}"
        elsif href =~ %r{/([^/]+)\.xml$}
          "express:#{::Regexp.last_match(1)}"
        else
          href
        end
      end
    end
  end
end
