# frozen_string_literal: true

module Suma
  # Validates that every cross-reference a rendered schema document emits
  # resolves inside it. The Expressir hyperlinked source emits xref macros
  # (`<<schema.entity,...>>`, `<<entity.attribute,...>>`); when a target is
  # missing, the renderer silently drops the link, so the check is done on
  # the source macros against the anchors present in the rendered HTML —
  # plus the reverse check that every in-page href hits an existing id.
  class AnchorValidator
    XREF_PATTERN = /<<([^,>]+)(?:,[^>]*)?>>/
    ID_PATTERN = /id="([^"]+)"/
    FRAGMENT_PATTERN = /href="#([^"]+)"/

    # @param directory [String] tree of compiled schema docs (doc_*.adoc
    #   with their rendered doc_*.html)
    def initialize(directory)
      @directory = directory
    end

    # @return [Array<LinkValidationResult>] dead links (empty = valid)
    def validate
      Dir.glob(File.join(@directory, "**", "doc_*.adoc"))
        .flat_map { |adoc| validate_document(adoc) }
    end

    private

    def validate_document(adoc)
      html = adoc.sub(/\.adoc\z/, ".html")
      return [missing_html(adoc, html)] unless File.file?(html)

      content = File.read(adoc)
      ids, fragments = rendered_digests(html)

      xref_violations(adoc, content, ids, fragments) +
        fragment_violations(html, ids)
    end

    def rendered_digests(html)
      rendered = File.read(html)
      [rendered.scan(ID_PATTERN).flatten.uniq,
       rendered.scan(FRAGMENT_PATTERN).flatten.uniq]
    end

    def xref_violations(adoc, content, ids, fragments)
      content.scan(XREF_PATTERN).flatten.uniq.filter_map do |target|
        next if cross_document?(target) || resolved?(target, ids, fragments)

        LinkValidationResult.new(
          file: adoc, line: nil, link: target,
          reason: "cross-reference has no anchor in the rendered document"
        )
      end
    end

    def fragment_violations(html, ids)
      File.read(html).scan(FRAGMENT_PATTERN).flatten.uniq.filter_map do |frag|
        next if ids.include?(frag)

        LinkValidationResult.new(
          file: html, line: nil, link: "##{frag}",
          reason: "in-page link points at no anchor in the document"
        )
      end
    end

    # Xrefs that cross documents (Asciidoctor `path.adoc#anchor` syntax)
    # resolve against other pages and are out of scope here.
    def cross_document?(target)
      target.include?("/") || target.include?("#")
    end

    def resolved?(target, ids, fragments)
      ids.include?(target) || fragments.include?(target)
    end

    def missing_html(adoc, html)
      LinkValidationResult.new(
        file: adoc, line: nil, link: html,
        reason: "no rendered HTML next to the adoc source"
      )
    end
  end
end
