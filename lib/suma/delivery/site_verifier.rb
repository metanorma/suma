# frozen_string_literal: true

require "json"
require "pathname"
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

      Report = Struct.new(:report, keyword_init: true) do
        def broken_count
          report["broken_links"].size + report["broken_fragments"].size
        end

        def to_json(*)
          JSON.generate(report)
        end
      end

      def initialize(site_dir, check_fragments: true)
        @site_dir = Pathname.new(site_dir)
        @check_fragments = check_fragments
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
