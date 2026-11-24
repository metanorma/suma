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

    Violation = Struct.new(:file, :type, :detail, keyword_init: true) do
      # The stable identity compared across runs for baseline gating:
      # file, violation class, and the marker/image that violates.
      def key
        "#{file}|#{type}|#{detail}"
      end
    end

    # One standing violation's stable identity for baseline comparison:
    # "<exp path>|<type>|<marker-or-image>".
    class Entry < Lutaml::Model::Serializable
      attribute :key, :string

      key_value do
        map "key", to: :key
      end
    end

    # Serializable violation report / baseline (same wire shape), the
    # MappingDrift pattern: a committed baseline floors the standing
    # violations so only NEW ones fail the build.
    class Report < Lutaml::Model::Serializable
      attribute :entries, Entry, collection: true

      key_value do
        map "entries", to: :entries
      end

      def keys
        entries.map(&:key)
      end

      def self.from_violations(violations)
        new(entries: violations.map { |v| Entry.new(key: v.key) })
      end
    end

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
      # Violation keys (and displays) carry the path relative to the
      # manifest, so a committed baseline matches on every machine and
      # in CI - absolute paths would key to one checkout.
      @base = File.dirname(File.expand_path(manifest_path))
      manifest = Expressir::SchemaManifest.from_file(manifest_path)
      manifest.schemas.each { |entry| validate_file(entry.path.to_s) }
      summary
    end

    def validate_file(path)
      body = File.read(path)
      @checked_schemas += 1
      scan_svgmap_blocks(body) do |block_body|
        validate_block(relative(path), block_body, path)
      end
    rescue StandardError => e
      @violations << Violation.new(file: relative(path),
                                   type: "unreadable_file", detail: e.message)
    end

    def scan_svgmap_blocks(body, &)
      body.scan(REMARK_BLOCK_RE) do |_schema, remark_body|
        remark_body.scan(SVGMAP_BLOCK_RE) do |(block_body)|
          yield(block_body)
        end
      end
    end

    def summary
      Result.new(violations: violations, checked_schemas: @checked_schemas,
                 checked_blocks: @checked_blocks)
    end

    private

    # +rel+ keys and displays the violation; +abs+ locates the diagram.
    def validate_block(rel, block_body, abs)
      @checked_blocks += 1
      images = block_body.scan(IMAGE_RE).flatten
      markers = block_body.scan(MARKER_RE).flatten
      check_images(rel, abs, images)
      check_markers(rel, markers, svg_shapes(abs, images.first))
    end

    def check_images(rel, abs, images)
      images.reject { |image| image_path(abs, image) }
        .each do |image|
          @violations << Violation.new(file: rel, type: "missing_image",
                                       detail: image)
        end
    end

    def check_markers(rel, markers, shapes)
      return if shapes.nil?

      markers.reject { |marker| shapes.include?(marker) }
        .each do |marker|
          @violations << Violation.new(file: rel, type: "missing_shape",
                                       detail: marker)
        end
      (shapes - markers).each do |shape|
        @violations << Violation.new(file: rel, type: "unlisted_shape",
                                     detail: shape)
      end
    end

    def relative(path)
      return path unless @base

      prefix = "#{@base}#{File::SEPARATOR}"
      path.start_with?(prefix) ? path.delete_prefix(prefix) : path
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
