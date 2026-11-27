# frozen_string_literal: true

require "pathname"
require "leptris"

module Suma
  module Delivery
    # Binds the cross-schema svgmap hotspots on the schema doc pages.
    #
    # Schema pages compile standalone (SchemaCompiler -> one Metanorma
    # document render), and a standalone render binds only in-document
    # targets: the source svgmaps' `<<express:other_schema[.entity]>>`
    # items reach the page as eref targets no bibliography entry covers,
    # and their figure hotspots keep the raw ordinal hrefs the SVG sources
    # carry. The collection renderer's reference-anchor resolvers never
    # see these pages - the collection manifest carries the part
    # documents, not the schema pages - so the hotspots ship dead
    # (iso-10303#891: the schema-page figure restoration exposed the gap;
    # the same figures were lost whole before).
    #
    # The binding data survives the standalone render: the page's
    # presentation XML keeps every svgmap's `<target href="N">` erefs,
    # keyed by the ordinal each figure's SVG markers carry (Vectory
    # remaps hotspots by that href value). This pass rewrites the ordinal
    # hotspots onto the owning schema pages
    # (`../<schema>/doc_<schema>.html#<schema>.<entity>`), checking each
    # target against the anchor index of the schema_docs tree; targets
    # with no live anchor (WG 12 source data referencing undeclared
    # elements) keep their ordinals and stay visible to the verifier's
    # hotspot gate.
    #
    # Idempotent: a bound anchor no longer carries an integer href.
    class SvgmapBinder
      Result = Struct.new(:pages, :bound, :skipped, keyword_init: true)

      BIBID_RE = /\Aexpress_(.+)\z/
      ORDINAL_RE = /\A\d+\z/

      def initialize(docs_dir)
        @docs_dir = Pathname.new(docs_dir)
      end

      def bind
        index = anchor_index
        results = doc_pages.map { |html| bind_page_or_skip(html, index) }
        Result.new(
          pages: results.count { |_, skipped| skipped.nil? },
          bound: results.sum(&:first),
          skipped: results.filter_map(&:last),
        )
      end

      private

      # Returns [bound hotspot count, skipped page rel path or nil].
      def bind_page_or_skip(html, index)
        pres = presentation_path(html)
        return [0, rel_path(html)] unless pres.file?

        [bind_page(html, pres, index), nil]
      end

      def doc_pages
        Pathname.glob(@docs_dir.join("*/doc_*.html"))
          .reject { |f| f.to_s.end_with?(".err.html") }.sort
      end

      def presentation_path(html)
        html.sub(/\.html\z/, ".presentation.xml")
      end

      def rel_path(path)
        path.relative_path_from(@docs_dir).to_s
      end

      def anchor_index
        doc_pages.to_h do |html|
          ids = Leptris::XML.parse_html(html.read).css("[id]")
            .map { |el| el["id"] }.uniq
          [rel_path(html), ids]
        end
      end

      # One figure's ordinal => bibitemid map per svgmap; targets already
      # carrying link/xref children are resolved targets the page binds
      # itself and are not touched.
      def figure_maps(pres)
        doc = Leptris::XML.parse(pres.read)
        doc.xpath("//*[local-name() = 'svgmap']").filter_map do |svgmap|
          targets = ordinal_map(svgmap)
          [figure_anchor(svgmap), targets] if targets.any?
        end
      end

      def figure_anchor(svgmap)
        svgmap.xpath("./*[local-name() = 'figure']")&.first&.[]("anchor")
      end

      def ordinal_map(svgmap)
        svgmap.xpath(".//*[local-name() = 'target']")
          .each_with_object({}) do |target, map|
          bib = eref_bibitemid(target)
          map[target["href"]] = bib if bib && target["href"]
        end
      end

      def eref_bibitemid(target)
        target.xpath("./*[local-name() = 'eref']")&.first&.[]("bibitemid")
      end

      def bind_page(html, pres, index)
        doc = Leptris::XML.parse_html(html.read)
        bound = bind_presented_figures(doc, pres, index, rel_path(html))
        bound += bind_stamped_anchors(doc, index, rel_path(html))
        dirty = bound.positive? ||
          doc.xpath("//*[@data-svgmap-bibitemid]").any?
        html.write(doc.to_html) if dirty
        bound
      end

      # Binds each presented figure's ordinals; an ordinal whose target
      # carries no live anchor in THIS tree (a schema page another shard
      # owns) is stamped with its bibitemid, so a later pass over the
      # assembled tree - which sees every schema page - binds it.
      def bind_presented_figures(doc, pres, index, page_rel)
        figure_maps(pres).sum do |anchor, targets|
          figure = doc.xpath("//*[@id = '#{anchor}']")&.first
          next 0 unless figure

          bind_figure(figure, targets, index, page_rel)
        end
      end

      def bind_figure(figure, targets, index, page_rel)
        figure.xpath(".//*[local-name() = 'svg']//*[local-name() = 'a']")
          .sum { |a| bind_anchor(a, targets, index, page_rel) }
      end

      # Returns 1 when the anchor's href was rewritten.
      def bind_anchor(anchor, targets, index, page_rel)
        href = anchor["href"].to_s
        return 0 unless href.match?(ORDINAL_RE)

        bib = targets[href]
        record = resolve(bib, index, page_rel)
        return stamp_or_zero(anchor, bib) unless record

        anchor["href"] = record
        drop_stamp(anchor)
        1
      end

      def stamp_or_zero(anchor, bib)
        anchor["data-svgmap-bibitemid"] = bib if bib
        0
      end

      def drop_stamp(anchor)
        anchor.remove_attribute("data-svgmap-bibitemid") if
          anchor["data-svgmap-bibitemid"]
      end

      # Binds anchors a previous pass stamped with their bibitemid; the
      # ordinal stays when this tree still lacks the target.
      def bind_stamped_anchors(doc, index, page_rel)
        doc.xpath("//*[local-name() = 'a'][@data-svgmap-bibitemid]")
          .sum do |a|
          next 0 unless a["href"].to_s.match?(ORDINAL_RE)

          record = resolve(a["data-svgmap-bibitemid"], index, page_rel)
          next 0 unless record

          a["href"] = record
          a.remove_attribute("data-svgmap-bibitemid")
          1
        end
      end

      # Returns the page-relative href for an `express_<schema>[.<entity>]`
      # bibitemid, or nil when the target carries no live anchor.
      def resolve(bibitemid, index, page_rel)
        parsed = parse_bibid(bibitemid) or return nil
        schema, anchor = parsed

        target_rel = "#{schema}/doc_#{schema}.html"
        ids = index[target_rel] or return nil
        return nil unless ids.include?(anchor)

        return "##{anchor}" if target_rel == page_rel

        "../#{target_rel}##{anchor}"
      end

      # [owning schema dir, anchor id] for `express_<schema>[.<entity>]`;
      # nil for anything else. A trailing ISO stamp chain trims away:
      # stamps announce themselves with an uppercase letter or a digit,
      # entity names are lowercase snake_case.
      def parse_bibid(bibitemid)
        m = BIBID_RE.match(bibitemid.to_s) or return nil

        if m[1].include?(".")
          schema, entity_full = m[1].split(".", 2)
          [schema, "#{schema}.#{stamp_trim(entity_full)}"]
        else
          schema = stamp_trim(m[1])
          [schema, schema]
        end
      end

      def stamp_trim(name)
        segments = name.split("_")
        kept = segments.take_while { |segment| segment !~ /[A-Z0-9]/ }
        kept.empty? ? name : kept.join("_")
      end
    end
  end
end
