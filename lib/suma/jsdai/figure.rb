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
        if @xml.img.areas && !@xml.img.areas.empty?
          area_parts = @xml.img.areas.each_with_index.map do |area, index|
            shape_element = generate_shape_element(area)
            "<a href=\"#{index + 1}\">#{shape_element}</a>"
          end

          svg_parts << area_parts.join
        end
        svg_parts << "\n\t\t</svg>"
        svg_parts.join
      end

      def to_exp
        basename = File.basename(@xml_file, ".xml")
        schema_name = extract_schema_name(basename)
        anchor_id = extract_anchor_id(basename)

        exp_parts = []
        exp_parts << "(*\"#{schema_name}.__expressg\""
        exp_parts << "\n[[#{anchor_id}]]"
        exp_parts << "\n[.svgmap]"
        exp_parts << "\n===="
        exp_parts << "\nimage::#{basename}.svg[]"

        if @xml.img.areas && !@xml.img.areas.empty?
          exp_parts << "\n"
          @xml.img.areas.each_with_index do |area, index|
            target = extract_target_from_href(area.href)
            exp_parts << "\n* <<#{target}>>; #{index + 1}"
          end
        end

        exp_parts << "\n===="
        exp_parts << "\n*)\n"
        exp_parts.join
      end

      private

      def generate_shape_element(area)
        shape_attrs = []
        shape_attrs << 'onmouseout="this.style.opacity=0" '
        shape_attrs << 'onmouseover="this.style.opacity=1" '
        shape_attrs << 'style="opacity: 0; fill: rgb(33, 128, 255); '
        shape_attrs << "fill-opacity: 0.3; stroke: rgb(0, 128, 255); "
        shape_attrs << "stroke-width: 1px; stroke-linecap: butt; "
        shape_attrs << 'stroke-linejoin: miter; stroke-opacity: 1;" '

        case area.shape
        when "rect"
          coords = parse_rect_coords(area.coords)
          shape_attrs << "height=\"#{coords[:height]}\" "
          shape_attrs << "width=\"#{coords[:width]}\" "
          shape_attrs << "y=\"#{coords[:y]}\" "
          shape_attrs << "x=\"#{coords[:x]}\"/>"
          "<rect #{shape_attrs.join}"
        when "poly", "polygon"
          shape_attrs << "points=\"#{area.coords}\"/>"
          "<polygon #{shape_attrs.join}"
        else
          # Unsupported shape, default to rectangle
          coords = parse_rect_coords(area.coords)
          shape_attrs << "height=\"#{coords[:height]}\" "
          shape_attrs << "width=\"#{coords[:width]}\" "
          shape_attrs << "y=\"#{coords[:y]}\" "
          shape_attrs << "x=\"#{coords[:x]}\"/>"
          "<rect #{shape_attrs.join}"
        end
      end

      def parse_rect_coords(coords_str)
        parts = coords_str.split(",").map(&:to_i)
        {
          x: parts[0],
          y: parts[1],
          width: parts[2] - parts[0],
          height: parts[3] - parts[1],
        }
      end

      def parse_coords(coords_str)
        parse_rect_coords(coords_str)
      end

      def extract_anchor_id(basename)
        # For module schemas like "armexpg1" with module="activity"
        # Result should be "Activity_arm_expg1"
        # For resource schemas like "action_schemaexpg2"
        # Result should be "action_schema_expg2"

        if basename =~ /^(arm|mim)expg(\d+)$/
          # Module schema: use schema_name + _expg + number
          schema_name = extract_schema_name(basename)
          "#{schema_name}_expg#{::Regexp.last_match(2)}"
        else
          # Resource schema: insert underscore before expg
          basename.sub("expg", "_expg")
        end
      end

      def extract_schema_name(basename)
        # For module schemas like "armexpg1" with module="activity"
        # Result should be "Activity_arm"
        # For resource schemas like "action_schemaexpg2"
        # Result should be "action_schema"

        if basename =~ /^(arm|mim)expg\d+$/
          # Module schema: use XML module attribute + arm/mim
          # Capitalize only the first letter of the module name
          module_name = @xml.module.split("_").map.with_index do |part, idx|
            idx.zero? ? part.capitalize : part
          end.join("_")
          "#{module_name}_#{::Regexp.last_match(1)}"
        else
          # Resource schema: strip expg suffix
          basename.sub(/expg\d+$/, "")
        end
      end

      def extract_target_from_href(href)
        # Extract the target from href
        # Type 1: "../../resources/action_schema/action_schema.xml#action_schema.as_name_attribute_select"
        #   → "express:action_schema.as_name_attribute_select"
        # Type 2: "../../resources/basic_attribute_schema/basic_attribute_schema.xml"
        #   → "express:basic_attribute_schema"
        # Type 3: "../activity_method/armexpg1.xml"
        #   → "Activity_method_arm_expg1"
        # Type 4: "../../resources/geometry_schema/geometry_schemaexpg3.xml"
        #   → "geometry_schema_expg3" (image reference in same resource)

        case href
        when /#(.+)$/
          # Has fragment - use it as entity reference
          "express:#{::Regexp.last_match(1)}"
        when %r{^\.\./([\w_]+)/(arm|mim)expg(\d+)\.xml$}
          # Module image reference like "../activity_method/armexpg1.xml"
          module_dir = ::Regexp.last_match(1)
          schema_type = ::Regexp.last_match(2)
          expg_num = ::Regexp.last_match(3)
          # Capitalize only the first letter of the module name
          module_name = module_dir.split("_").map.with_index do |part, idx|
            idx.zero? ? part.capitalize : part
          end.join("_")
          "#{module_name}_#{schema_type}_expg#{expg_num}"
        when %r{/([^/]+)expg(\d+)\.xml$}
          # Image reference to another diagram in same or different resource
          # e.g., "../../resources/geometry_schema/geometry_schemaexpg3.xml"
          # Result: "geometry_schema_expg3" (no "express:" prefix for images)
          schema_name = ::Regexp.last_match(1)
          expg_num = ::Regexp.last_match(2)
          "#{schema_name}_expg#{expg_num}"
        when %r{/([^/]+)\.xml$}
          # Resource schema reference (no expg)
          "express:#{::Regexp.last_match(1)}"
        else
          href
        end
      end
    end
  end
end
