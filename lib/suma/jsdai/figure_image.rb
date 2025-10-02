# frozen_string_literal: true

require "base64"

module Suma
  module Jsdai
    # Represents a JSDAI figure image file
    class FigureImage
      attr_reader :path, :width, :height

      def initialize(image_file)
        @path = image_file
        @base64_data = nil
        @width = nil
        @height = nil
        @image_type = extract_image_type
      end

      def to_base64
        @base64_data ||= begin
          image_data = File.binread(@path)
          "data:image/#{@image_type};base64,#{Base64.strict_encode64(image_data)}"
        end
      end

      def dimensions
        extract_dimensions unless @width && @height
        [@width, @height]
      end

      private

      def extract_image_type
        File.extname(@path).delete(".").downcase
      end

      def extract_dimensions
        case @image_type
        when "gif"
          extract_gif_dimensions
        when "jpg", "jpeg"
          extract_jpeg_dimensions
        else
          raise "Unsupported image type: #{@image_type}"
        end
      end

      def extract_gif_dimensions
        # Read GIF header to extract dimensions
        # GIF87a and GIF89a format: width at bytes 6-7, height at bytes 8-9
        File.open(@path, "rb") do |file|
          file.read(6) # Skip "GIF87a" or "GIF89a"
          width_bytes = file.read(2)
          height_bytes = file.read(2)

          @width = width_bytes.unpack1("S<") # Little-endian short
          @height = height_bytes.unpack1("S<")
        end
      end

      def extract_jpeg_dimensions
        # Read JPEG file to extract dimensions
        # JPEG uses markers, we look for SOF (Start of Frame) markers
        File.open(@path, "rb") do |file|
          # Check for JPEG magic number
          return unless file.read(2) == "\xFF\xD8".b

          loop do
            marker = file.read(2)
            break unless marker

            # SOF markers: 0xFFC0-0xFFC3, 0xFFC5-0xFFC7, 0xFFC9-0xFFCB, 0xFFCD-0xFFCF
            if marker[0] == "\xFF".b &&
               (marker[1].ord >= 0xC0 && marker[1].ord <= 0xCF) &&
               marker[1].ord != 0xC4 && marker[1].ord != 0xC8 && marker[1].ord != 0xCC
              file.read(3) # Skip length (2 bytes) and precision (1 byte)
              height_bytes = file.read(2)
              width_bytes = file.read(2)
              @height = height_bytes.unpack1("n") # Big-endian short
              @width = width_bytes.unpack1("n")
              break
            end

            # Skip this marker's data
            length = file.read(2)&.unpack1("n")
            break unless length

            file.seek(length - 2, IO::SEEK_CUR)
          end
        end
      end
    end
  end
end
