# frozen_string_literal: true

require "thor"
require_relative "../thor_ext"
require_relative "../jsdai/figure"
require "fileutils"

module Suma
  module Cli
    # ConvertJsdai command to convert JSDAI XML and image to SVG and EXP
    class ConvertJsdai < Thor
      desc "convert_jsdai XML_FILE IMAGE_FILE OUTPUT_DIR",
           "Convert JSDAI XML and image files to SVG and EXP files"

      def convert_jsdai(xml_file, image_file, output_dir)
        xml_file = File.expand_path(xml_file)
        image_file = File.expand_path(image_file)
        output_dir = File.expand_path(output_dir)

        unless File.exist?(xml_file)
          raise Errno::ENOENT, "XML file not found: #{xml_file}"
        end

        unless File.exist?(image_file)
          raise Errno::ENOENT, "Image file not found: #{image_file}"
        end

        unless File.file?(xml_file)
          raise ArgumentError, "Specified path is not a file: #{xml_file}"
        end

        unless File.file?(image_file)
          raise ArgumentError, "Specified path is not a file: #{image_file}"
        end

        run(xml_file, image_file, output_dir)
      end

      private

      def run(xml_file, image_file, output_dir)
        FileUtils.mkdir_p(output_dir)

        figure = Suma::Jsdai::Figure.new(xml_file, image_file)
        basename = File.basename(xml_file, ".xml")

        svg_output = File.join(output_dir, "#{basename}.svg")
        exp_output = File.join(output_dir, "#{basename}.exp")

        puts "Converting JSDAI files..."
        File.write(svg_output, figure.to_svg)
        puts "Generated SVG: #{svg_output}"

        File.write(exp_output, figure.to_exp)
        puts "Generated EXP: #{exp_output}"

        puts "Conversion complete."
      end
    end
  end
end
