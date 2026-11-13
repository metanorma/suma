# frozen_string_literal: true

require "pathname"
require "leptris"

module Suma
  module Delivery
    # Assembly-time cross-page fragment resolution (the delivery
    # correctness model's final pass): per-document rendering writes
    # term-fragment and svgmap-hotspot hrefs page-locally, and the
    # unioned site holds their targets on other pages. Two resolution
    # rules, both requiring a unique site-wide match:
    #
    # 1. the fragment id exists on exactly one other page — the href
    #    repoints at that page;
    # 2. the fragment names a declaration whose rendered anchor carries
    #    the stamped form `<scope>_ISO_…` with scope ending in
    #    `.<fragment>` (or equal to it) — the href repoints at the page
    #    rendering that anchor, at the full stamped id.
    #
    # Ambiguous matches (two or more candidate pages/anchors) stay
    # untouched: guessing a target would be wrong exactly like an
    # unresolved one.
    class CrossPageFragments
      SCOPE_PART = /[A-Za-z0-9-]+_[0-9]+/
      # `<scope>_ISO_<doc>_<year>` — the scope captures as `schema` or
      # `schema.entity`.
      SCOPED_ID_RE = /\A([a-z][a-z0-9_]*(?:\.[a-z0-9_.]+)?)_ISO_#{SCOPE_PART}/

      Result = Struct.new(:own, :remapped, :ambiguous, :unresolved,
                          keyword_init: true)

      def initialize(site_dir)
        @site_dir = Pathname.new(site_dir)
      end

      def repair
        pages = html_pages
        id_index = index_ids(pages)
        counts = Hash.new(0)
        pages.each do |path, doc|
          remap_page(doc, path, id_index, counts)
          path.write(doc.to_html)
        end
        Result.new(**counts.slice(:own, :remapped, :ambiguous, :unresolved))
      end

      private

      def remap_page(doc, path, id_index, counts)
        doc.css("a[href^='#']").each do |a|
          status, href = resolve(a["href"].to_s.delete_prefix("#"),
                                 path, id_index)
          status = :unresolved if status.nil?
          counts[status] += 1
          a["href"] = href if href
        end
      end

      # [status, href-or-nil]: :own = the target id is on the citing
      # page (fine as written); :ambiguous = several candidates;
      # :unresolved = no candidate; :remapped carries the new href.
      def resolve(frag, path, id_index)
        exact = id_index[frag]
        if exact
          uniq = exact[:pages].uniq
          return [:own] if uniq == [path]
          return [:ambiguous] if uniq.size > 1

          return [:remapped, cross_href(path, uniq.first, frag)]
        end

        scoped_resolve(frag, path, id_index)
      end

      def scoped_resolve(frag, path, id_index)
        candidates = matching_scopes(frag, path, id_index)
        return [:ambiguous] if candidates.size > 1

        id, pages = candidates.first
        return [:unresolved, nil] unless id

        [:remapped, cross_href(path, pages.first, id)]
      end

      # [id, pages] pairs for stamped anchors whose scope names the
      # fragment, rendered on some page other than the citing one.
      def matching_scopes(frag, path, id_index)
        id_index.filter_map do |id, entry|
          pages = entry[:pages].uniq
          next if pages == [path]

          scope = scope_of(id)
          next unless scope && (scope == frag || scope.end_with?(".#{frag}"))

          [id, pages]
        end
      end

      def scope_of(id)
        SCOPED_ID_RE.match(id)&.[](1)
      end

      def cross_href(path, page, fragment)
        "#{relative_href(path, page)}##{fragment}"
      end

      def relative_href(from, to)
        # The path FROM the citing page's directory TO the target page's
        # own location. Joining the target's basename loses its directory:
        # a schema-doc page citing a member page then emitted
        # `member_0.xml.11.html#…`, unresolvable from schema_docs/ depth
        # (TRThurman, iso-10303#835 — every remapped link broke).
        to.realpath.relative_path_from(from.dirname.realpath).to_s
      rescue Errno::ENOENT
        # The target page does not exist on disk; leave the relative
        # computation to fail softly by naming the page as stored.
        to.basename.to_s
      end

      def html_pages
        @html_pages ||= @site_dir.glob("**/*.html")
          .reject { |p| p.basename.to_s.end_with?(".err.html") }
          .to_h { |p| [p, Leptris::XML.parse_html(p.read)] }
      end

      # fragment id → { pages: [path, …] }. A plain hash: reads of
      # unknown ids must not insert (matching_scopes iterates the index
      # afterwards).
      def index_ids(pages)
        index = {}
        pages.each do |path, doc|
          doc.css("[id]").each do |el|
            next if (id = el["id"]).nil? || id.empty?

            (index[id] ||= { pages: [] })[:pages] << path
          end
        end
        index
      end
    end
  end
end
