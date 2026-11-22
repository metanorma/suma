# frozen_string_literal: true

module Suma
  module Delivery
    # Corpus-side gate thresholds for `delivery verify --expectations`:
    # the measured site-shape conditions as data, so the calling workflow
    # states its delivery contract in one manifest instead of hand-rolled
    # shell checks. Unset attributes are not checked.
    class Expectations < Lutaml::Model::Serializable
      attribute :sections_min, :integer
      attribute :index_pages, :integer
      attribute :schema_attachments_min, :integer
      attribute :schema_docs_min, :integer
      attribute :missing_express_max, :integer, default: -> { 0 }
      attribute :broken_links_max, :integer, default: -> { 0 }
      # Category => rule => maximum live diagnostic rows: the stable
      # identity of an err.html row is category + rule, not the code,
      # which migrates across metanorma releases (iso-10303#859).
      attribute :diagnostics_max, :hash
      # Page-shape gate maxima over the verifier's page-shape census
      # (TRThurman, iso-10303#857). The path prefixes scanned for
      # build-directory leakage default to the verifier's list; set
      # them here to override.
      attribute :forbidden_path_prefixes, :string, collection: true
      attribute :build_dir_references_max, :integer, default: -> { 0 }
      attribute :incomplete_listings_max, :integer, default: -> { 0 }
      attribute :missing_schema_remarks_max, :integer, default: -> { 0 }
      attribute :asciidoc_leaks_max, :integer, default: -> { 0 }

      key_value do
        map "sections_min", to: :sections_min
        map "index_pages", to: :index_pages
        map "schema_attachments_min", to: :schema_attachments_min
        map "schema_docs_min", to: :schema_docs_min
        map "missing_express_max", to: :missing_express_max
        map "broken_links_max", to: :broken_links_max
        map "diagnostics_max", to: :diagnostics_max
        map "forbidden_path_prefixes", to: :forbidden_path_prefixes
        map "build_dir_references_max", to: :build_dir_references_max
        map "incomplete_listings_max", to: :incomplete_listings_max
        map "missing_schema_remarks_max", to: :missing_schema_remarks_max
        map "asciidoc_leaks_max", to: :asciidoc_leaks_max
      end

      # Human-readable violation lines for every threshold the +report+
      # and +broken_links+ breach; unset thresholds stay silent. The name
      # suffix is the comparison: `_min` floors, `_max` caps, a bare name
      # (index_pages) is exact. The nested diagnostics_max thresholds
      # count against the report's diagnostics census.
      def violations(report, broken_links)
        threshold_violations(report, broken_links) +
          diagnostics_violations(report["diagnostics"])
      end

      PAGE_SHAPE_PAGE_KEYS = {
        "build_dir_references_max" => "build_dir_pages",
        "incomplete_listings_max" => "incomplete_listings",
        "missing_schema_remarks_max" => "missing_schema_remarks",
        "asciidoc_leaks_max" => "asciidoc_leak_pages",
      }.freeze

      MAX_DETAIL_PAGES = 20

      private

      def threshold_violations(report, broken_links)
        actuals(report, broken_links).filter_map do |name, actual|
          limit = public_send(name) or next
          relation = relation_of(name)
          next if relation_met?(relation, actual, limit)

          line = format("%<name>s: got %<actual>d, expected %<relation>s " \
                        "%<limit>d", name: name, actual: actual,
                                     relation: relation, limit: limit)
          detail = page_shape_detail(name, report)
          detail ? "#{line} (#{detail})" : line
        end
      end

      # The gate names what it counts: a page-shape violation carries the
      # offending pages, so a red run is a diagnosis and not another CI
      # round trip (2026-11-22: an unnamed 350-leak class cost a full
      # assemble cycle per guess).
      def page_shape_detail(name, report)
        pages = Array(report[PAGE_SHAPE_PAGE_KEYS[name]])
        return if pages.empty?

        shown = pages.first(MAX_DETAIL_PAGES).join(", ")
        rest = pages.size - MAX_DETAIL_PAGES
        rest.positive? ? "pages: #{shown}, +#{rest} more" : "pages: #{shown}"
      end

      # diagnostics_max: { "Referencing" => { "ISO_56" => 0 } }. A rule
      # absent from the census counts zero rows.
      def diagnostics_violations(census)
        Array(diagnostics_max).flat_map do |category, rules|
          rules.filter_map do |rule, limit|
            actual = (census || {}).dig(category, rule) || 0
            next if actual <= limit

            format("%<category>s/%<rule>s: got %<actual>d, expected at " \
                   "most %<limit>d", category: category, rule: rule,
                                     actual: actual, limit: limit)
          end
        end
      end

      def relation_of(name)
        return "at least" if name.end_with?("_min")
        return "at most" if name.end_with?("_max")

        "exactly"
      end

      def relation_met?(relation, actual, limit)
        case relation
        when "at least" then actual >= limit
        when "at most" then actual <= limit
        else actual == limit
        end
      end

      # Every threshold's observed value, keyed by threshold name. The
      # inventory carries the shape counts; missing_express_pages is a
      # top-level report key; the page-shape maxima count against the
      # verifier's page-shape census.
      def actuals(report, broken_links)
        inventory = report["inventory"] || {}
        {
          "sections_min" => inventory["sections"],
          "index_pages" => inventory["index_pages"],
          "schema_attachments_min" => inventory["schema_attachments"],
          "schema_docs_min" => inventory["schema_docs"],
          "missing_express_max" => Array(report["missing_express_pages"]).size,
          "broken_links_max" => broken_links.size,
          **page_shape_actuals(report),
        }
      end

      # The page-shape census (TRThurman, iso-10303#857): occurrences
      # for build-dir paths and asciidoc leaks, page counts for
      # incomplete listings and unpublished remarks.
      def page_shape_actuals(report)
        {
          "build_dir_references_max" => report["build_dir_occurrences"].to_i,
          "incomplete_listings_max" =>
            Array(report["incomplete_listings"]).size,
          "missing_schema_remarks_max" =>
            Array(report["missing_schema_remarks"]).size,
          "asciidoc_leaks_max" => report["asciidoc_leak_occurrences"].to_i,
        }
      end
    end
  end
end
