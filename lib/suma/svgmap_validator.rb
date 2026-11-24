# frozen_string_literal: true

module Suma
  # Source-layer gate for the EXPRESS-G figure hotspots (TRThurman,
  # iso-10303#875): a schema's `__expressg` remark carries `[.svgmap]`
  # blocks whose image references and ordinal markers the render binds
  # to the SVG's anchor-wrapped shapes. A block naming a missing image,
  # a marker with no wrapped shape, or an SVG anchor no list entry
  # covers produces a hotspot that can never bind - the residual class
  # the site-level gate counts only after a full render. This validator
  # states the same contract at the source, in seconds, per schema.
  class SvgmapValidator
    Result = Struct.new(:violations, :checked_schemas, :checked_blocks,
                        keyword_init: true)

    Violation = Struct.new(:file, :type, :detail, keyword_init: true)

    REMARK_BLOCK_RE = /
      \(\*"(?<schema>[^"]+)\.__expressg"\s*\n
      (?<body>.*?)
      \n\*\)
    /xm
    SVGMAP_BLOCK_RE = /
      \[\.svgmap\]\s*^====\s*$
      (?<body>.*?)
      ^====\s*$
    /xm
    IMAGE_RE = /image::\s*([^\[\]\s]+)/
    MARKER_RE = /^\s*\*\s*<<[^>]*>>\s*;\s*(?<marker>\S+)\s*$/

    attr_reader :violations

    def initialize
      @violations = []
      @checked_schemas = 0
      @checked_blocks = 0
    end

    def validate_manifest(manifest_path)
      manifest = Expressir::SchemaManifest.from_file(manifest_path)
      manifest.schemas.each { |entry| validate_file(entry.path.to_s) }
      summary
    end

    def validate_file(path)
      body = File.read(path)
      @checked_schemas += 1
      body.scan(REMARK_BLOCK_RE) do |_schema, remark_body|
        remark_body.scan(SVGMAP_BLOCK_RE) do |(block_body)|
          validate_block(path, block_body)
        end
      end
    rescue StandardError => e
      @violations << Violation.new(file: path, type: "unreadable_file",
                                   detail: e.message)
    end

    def summary
      Result.new(violations: violations, checked_schemas: @checked_schemas,
                 checked_blocks: @checked_blocks)
    end

    private

    def validate_block(path, block_body)
      @checked_blocks += 1
      images = block_body.scan(IMAGE_RE).flatten
      markers = block_body.scan(MARKER_RE).flatten
      check_images(path, images)
      check_markers(path, markers, svg_shapes(path, images.first))
    end

    def check_images(path, images)
      images.reject { |image| image_path(path, image) }
        .each do |image|
          @violations << Violation.new(file: path, type: "missing_image",
                                       detail: image)
        end
    end

    def check_markers(path, markers, shapes)
      return if shapes.nil?

      markers.reject { |marker| shapes.include?(marker) }
        .each do |marker|
          @violations << Violation.new(file: path, type: "missing_shape",
                                       detail: marker)
        end
      (shapes - markers).each do |shape|
        @violations << Violation.new(file: path, type: "unlisted_shape",
                                     detail: shape)
      end
    end

    def image_path(exp_path, image)
      candidate = File.expand_path(image, File.dirname(exp_path))
      File.exist?(candidate) && candidate
    end

    # The wrapped shapes of the block's SVG, keyed by their href marker.
    # Nil when the image is missing or unparsable - the image-level
    # violation already covers the missing case, and an unparsable SVG
    # cannot state a marker contract.
    def svg_shapes(exp_path, image)
      return if image.nil?

      path = image_path(exp_path, image)
      return if path.nil?

      svg = File.read(path)
      doc = Leptris::XML.parse_html(svg)
      doc.xpath("//*[local-name() = 'a'][@href]")
        .map { |a| a["href"].to_s.strip }
        .reject(&:empty?)
    rescue StandardError
      nil
    end
  end
end
