# frozen_string_literal: true

require "json"
require "pathname"
require "expressir"
require "leptris"

module Suma
  module Delivery
    # Site-wide link verification (port of site_manifest.py verify_links):
    # every cross-file href in the stitched site must resolve to a file,
    # and every fragment must resolve to an anchor in its target file.
    # The production gate is zero broken links. Intra-file fragment hrefs
    # are reported but never fail the build — metanorma emits some whose
    # target is never defined (pre-existing upstream issues, not stitch
    # faults).
    class SiteVerifier
      # A faithful port: the metrics would fragment the link walk
      # without making it clearer.
      # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      SCHEME_RE = %r{\A(?:https?:|mailto:|javascript:|data:)}

      # Metanorma's unresolved-citation rendering prefix; a page carrying
      # it cites an express reference the corpus never resolved.
      MISSING_EXPRESS_MARKER = "Missing:express"

      # Build-environment paths a published page must never name
      # (TRThurman, iso-10303#857): paths pointing outside the site root
      # have no meaning at delivery. Overridable per expectations
      # through +forbidden_path_prefixes+.
      DEFAULT_FORBIDDEN_PATH_PREFIXES =
        %w[/home/ /Users/ /private/var/ /tmp/].freeze

      # The whitespace-normalized fragment of a schema's first own
      # remark that its schema-doc page must carry.
      REMARK_EXCERPT_LENGTH = 40

      # Express listings end with the schema-close token; a schema-doc
      # page whose last token renders outside a listing element closed
      # its <pre> early and leaked the tail as normal HTML.
      END_SCHEMA_TOKEN = "END_SCHEMA;"

      # Asciidoc constructs that must never render as page text
      # (source-authoring residuals): inline macros plus the bare
      # forced-line-break "+".
      ASCIIDOC_MACROS_RE = /\b(?:image|link|include)::[^ \t\r\n]*\[\]/
      LISTING_TAGS = %w[pre code].freeze

      Report = Struct.new(:report, keyword_init: true) do
        def broken_count
          report["broken_links"].size + report["broken_fragments"].size
        end

        def to_json(*)
          JSON.generate(report)
        end
      end

      def initialize(site_dir, check_fragments: true,
                     forbidden_path_prefixes: nil)
        @site_dir = Pathname.new(site_dir)
        @check_fragments = check_fragments
        prefixes = Array(forbidden_path_prefixes)
        @forbidden_path_prefixes =
          prefixes.empty? ? DEFAULT_FORBIDDEN_PATH_PREFIXES : prefixes
        @forbidden_path_re =
          %r{#{Regexp.union(@forbidden_path_prefixes)}[\w./+-]*}
      end

      def verify
        report = empty_report
        anchor_index = build_anchor_index
        html_files.each do |html_file|
          rel_path = html_file.relative_path_from(@site_dir).to_s
          content = html_file.read
          if content.include?(MISSING_EXPRESS_MARKER)
            report["missing_express_pages"] << rel_path
          end
          doc = Leptris::XML.parse_html(content)
          verify_intra_fragments(doc, rel_path, html_file, report)
          verify_links(doc, rel_path, html_file, anchor_index, report)
          check_build_dir_references(content, rel_path, report)
          check_asciidoc_leakage(doc, rel_path, report)
          check_page_inventory(doc, rel_path, report)
          next unless schema_doc_page?(rel_path)

          check_listing_completeness(doc, rel_path, report)
          check_own_remark(doc, rel_path, report)
        end
        report["inventory"] = site_inventory
        report["diagnostics"] = Diagnostics.count_site(@site_dir).to_h
        Report.new(report: report)
      end

      private

      def empty_report
        {
          "total_links" => 0,
          "resolved_links" => 0,
          "broken_links" => [],
          "total_fragments" => 0,
          "resolved_fragments" => 0,
          "broken_fragments" => [],
          "cross_document_links" => 0,
          "total_intra_fragments" => 0,
          "resolved_intra_fragments" => 0,
          "broken_intra_fragments" => [],
          "missing_express_pages" => [],
          "build_dir_pages" => [],
          "build_dir_occurrences" => 0,
          "incomplete_listings" => [],
          "missing_schema_remarks" => [],
          "asciidoc_leak_pages" => [],
          "asciidoc_leak_occurrences" => 0,
          "page_inventory" => {},
          "inventory" => {},
          "diagnostics" => {},
        }
      end

      # The stitched site's shape: the counts the delivery contract is
      # stated against (section pages, index pages, schema attachments,
      # schema doc pages).
      def site_inventory
        {
          "sections" => Dir.glob("#{@site_dir}/**/member_*.xml.*.html")
            .count { |f| !f.end_with?(".err.html") },
          "index_pages" => Dir.glob("#{@site_dir}/**/*_index.html").size,
          "schema_attachments" =>
            Dir.glob("#{@site_dir}/plain_schemas/**/*.exp").size,
          "schema_docs" => if Dir.exist?("#{@site_dir}/schema_docs")
                             Dir.children("#{@site_dir}/schema_docs").size
                           else
                             0
                           end,
        }
      end

      # Build-directory leakage: every occurrence of a path under a
      # forbidden prefix, page-level and occurrence-level.
      def check_build_dir_references(content, rel_path, report)
        hits = content.scan(@forbidden_path_re)
        return if hits.empty?

        report["build_dir_pages"] << rel_path
        report["build_dir_occurrences"] += hits.size
      end

      # Asciidoc source constructs leaked as rendered page text,
      # counted over text nodes only (markup-inside-attributes is not
      # leakage).
      def check_asciidoc_leakage(doc, rel_path, report)
        leaks = doc.xpath("//text()").sum do |node|
          # The annotated-EXPRESS source listing shows the macros as
          # written by design (the source-fidelity listing); only macros
          # rendered outside listings are leakage.
          next 0 if inside_listing?(node)

          text = node.text.to_s
          text.scan(ASCIIDOC_MACROS_RE).size + (text.strip == "+" ? 1 : 0)
        end
        return if leaks.zero?

        report["asciidoc_leak_pages"] << rel_path
        report["asciidoc_leak_occurrences"] += leaks
      end

      # The per-page inventory ratchet rides in the machine-readable
      # report: image and link counts per page.
      def check_page_inventory(doc, rel_path, report)
        report["page_inventory"][rel_path] = {
          "imgs" => doc.css("img").size,
          "links" => doc.css("a[href]").size,
        }
      end

      # Schema-doc pages only: a schema listing that closed early
      # renders its tail as normal HTML, so the final END_SCHEMA; token
      # no longer sits inside a listing element.
      def check_listing_completeness(doc, rel_path, report)
        return if listing_closes?(doc)

        report["incomplete_listings"] << rel_path
      end

      def listing_closes?(doc)
        tokens = doc.xpath("//text()")
        last = tokens.select do |node|
          node.text&.include?(END_SCHEMA_TOKEN)
        end.last
        last && inside_listing?(last)
      end

      def inside_listing?(node)
        current = node.parent
        while current
          return true if LISTING_TAGS.include?(current.name)

          current = current.parent
        end
        false
      end

      # A schema whose parsed attachment carries its own remarks must
      # publish them: the page text contains the whitespace-normalized
      # head of the first remark. Schemas without an attachment on the
      # site cannot be judged and are skipped.
      def check_own_remark(doc, rel_path, report)
        schema_id = File.basename(rel_path, ".html").delete_prefix("doc_")
        remarks = schema_remarks[schema_id]
        return if Array(remarks).empty?

        excerpt = whitespace_norm(remarks.first)[0, REMARK_EXCERPT_LENGTH]
        return if whitespace_norm(page_text(doc)).include?(excerpt)

        report["missing_schema_remarks"] << schema_id
      end

      # The page's whole text content (Leptris documents expose no
      # #text of their own).
      def page_text(doc)
        doc.xpath("//text()").map { |node| node.text.to_s }.join(" ")
      end

      def whitespace_norm(text)
        text.to_s.gsub(/\s+/, " ").strip
      end

      # One Expressir parse per schema attachment, reused across every
      # schema-doc page of the site.
      def schema_remarks
        @schema_remarks ||= Dir.glob("#{@site_dir}/plain_schemas/**/*.exp")
          .filter_map do |exp|
            begin
              schema = Expressir::Express::Parser.from_file(exp).schemas.first
            rescue Expressir::Express::Error::SchemaParseFailure => e
              warn "[suma] unparseable schema attachment: #{exp} " \
                   "(#{e.message.lines.first.to_s.strip})"
              next nil
            end
            next unless schema

            [File.basename(exp, ".exp"), schema.remarks]
          end.compact.to_h
      end

      def schema_doc_page?(rel_path)
        File.basename(rel_path).start_with?("doc_")
      end

      def html_files
        Dir.glob("#{@site_dir}/**/*.html")
          .reject { |f| f.end_with?(".err.html") }
          .sort.map { |f| Pathname.new(f) }
      end

      def anchors_of(path)
        Leptris::XML.parse_html(path.read).css("[id]").map { |n| n["id"] }.uniq
      end

      def build_anchor_index
        html_files.to_h do |html_file|
          rel = html_file.relative_path_from(@site_dir).to_s
          [rel, anchors_of(html_file)]
        end
      end

      def verify_intra_fragments(doc, rel_path, html_file, report)
        own_anchors = anchors_of(html_file)
        doc.css("a[href]").each do |a|
          href = a["href"].to_s.strip
          next unless href.start_with?("#") && href.length > 1

          fragment = href[1..]
          report["total_intra_fragments"] += 1
          if own_anchors.include?(fragment)
            report["resolved_intra_fragments"] += 1
          else
            report["broken_intra_fragments"] <<
              { "source" => rel_path, "fragment" => fragment }
          end
        end
      end

      def verify_links(doc, rel_path, html_file, anchor_index, report)
        source_dir = Pathname.new(rel_path).parent
        doc.css("a[href]").each do |a|
          href = a["href"].to_s.strip
          next if href.empty? || href.start_with?("#")
          next if href.match?(SCHEME_RE)

          # Bare integers are counted, not skipped: an unbound svgmap
          # hotspot emits its ordinal as the href, and a link to a
          # nonexistent file "12" is dead whatever the key form.

          file_part, fragment = href.split("#", 2)
          file_part = file_part.delete_prefix("./")

          report["total_links"] += 1
          target = html_file.parent / file_part
          unless target.exist?
            report["broken_links"] << {
              "source" => rel_path,
              "href" => fragment ? "#{file_part}##{fragment}" : file_part,
            }
            next
          end
          report["resolved_links"] += 1
          count_cross_document(source_dir, target, report)
          verify_fragment(fragment, target, rel_path, anchor_index, report)
        end
      end

      def count_cross_document(source_dir, target, report)
        target_rel = target.relative_path_from(@site_dir)
        return unless source_dir != target_rel.parent && source_dir.to_s != "."

        report["cross_document_links"] += 1
      rescue ArgumentError
        nil
      end

      def verify_fragment(fragment, target, rel_path, anchor_index, report)
        return unless fragment && @check_fragments

        report["total_fragments"] += 1
        target_rel = target.relative_path_from(@site_dir).to_s
        if anchor_index.fetch(target_rel, Set.new).include?(fragment)
          report["resolved_fragments"] += 1
        else
          report["broken_fragments"] << {
            "source" => rel_path,
            "href" => "#{target.basename}##{fragment}",
            "fragment" => fragment,
            "target_file" => target_rel,
          }
        end
      end
      # rubocop:enable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    end
  end
end
