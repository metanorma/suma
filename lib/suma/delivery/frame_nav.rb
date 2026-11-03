# frozen_string_literal: true

require "leptris"

module Suma
  module Delivery
    # Frame-navigation delivery postprocess (port of suma2srl.py): turns a
    # stitched site into the SRL frameset presentation.
    #
    # - index.html: strip Attachments, unwrap collection/document nesting,
    #   flatten the doc list, wire onclick handlers that drive the
    #   index+info frames, and add the frameset redirect script.
    # - every document index file: target="info" on all links.
    # - every section file: inject the CSS override suppressing
    #   metanorma's built-in sidebar (the left frame replaces it) with
    #   the DRAFT watermark. Idempotent on re-runs.
    class FrameNav
      # A faithful port: the constants carry the Python payload verbatim
      # and the metrics would fragment the pipeline without clarifying it.
      # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Layout/LineLength
      FRAMESET_JS = 'if(window.self===window.top)window.location.replace("srl_index.html");else window.addEventListener("pageshow",function(){try{parent.index.location="sys/frame_toc_short.htm"}catch(e){}});'

      CSS_OVERRIDE = '<style>nav{display:none !important}#toggle{display:none !important}body{margin-left:2em !important}body::after{content:"DRAFT";position:fixed;top:50%;left:50%;transform:translate(-50%,-50%) rotate(-45deg);font-size:8em;font-weight:bold;font-family:sans-serif;color:rgba(200,200,200,0.3);pointer-events:none;z-index:9999;}</style>'

      PREVIOUS_OVERRIDE_RE = %r{<style>nav\{display:none !important\}.*?</style>}m
      PREVIOUS_TOGGLE_RE = %r{<div id="toggle">\s*<span>[^<]*</span>\s*</div>}m

      def initialize(site_dir)
        @site_dir = Pathname.new(site_dir)
      end

      def process
        top_level = process_index
        add_target_attributes(top_level)
        strip_metanorma_sidebar
        top_level
      end

      private

      # -- index.html ---------------------------------------------------

      def process_index
        path = @site_dir / "index.html"
        doc = Leptris::XML.parse_html(path.read)
        strip_index_chrome(doc)
        top_level = build_top_level(doc)
        wire_index_links(doc, top_level)
        inject_frameset_script(doc)
        path.write(doc.to_html)
        top_level
      end

      def strip_index_chrome(doc)
        # Decompose the element containing the "Attachments" text: the
        # raw index nests the whole schema-exp attachment list inside that
        # <li>, so subtree removal drops all of it (Python decompose).
        doc.xpath("//text()[contains(., 'Attachments')]")
          .each { |t| t.parent.remove }
        # Unwrap two levels above every anchor text naming the collection
        # wrappers ("ISO Collection"/"Document"), then drop the text: the
        # per-document subtrees collapse into the flat list the frameset
        # nav expects. (Text-substring match, doc order, exactly like the
        # Python phase.)
        doc.xpath("//text()[contains(., 'ISO Collection') or " \
                  "contains(., 'Document')]").each do |t|
          unwrap(t.parent.parent) if t.parent&.parent
          unwrap(t.parent) if t.parent
          t.parent&.remove_child(t)
        end
        doc.xpath("//text()[contains(., 'STEP Resources Library')]")
          .each { |t| t.parent.remove_child(t) }
        doc.css("nav a").each do |a|
          next unless a.parent&.parent&.name == "ul"

          unwrap(a.parent.parent)
          unwrap(a.parent)
        end
      end

      # Replace the node with its children (BeautifulSoup's unwrap).
      def unwrap(node)
        node.children.each { |c| node.add_previous_sibling(c) }
        node.parent.remove_child(node)
      end

      # href -> the first page of that document (for the onclick target).
      # Single-file documents map to themselves; index files map to the
      # first <a href> inside them, prefixed with the href's subdirectory.
      def build_top_level(doc)
        top_level = {}
        doc.css("a").each do |a|
          href = a["href"]
          top_level[href] = href if href
        end
        top_level.each_key do |href|
          next unless File.basename(href).end_with?("_index.html")

          top_level[href] = first_page_of(href) || href
        end
        top_level
      end

      def first_page_of(href)
        doc_path = @site_dir / href
        return nil unless doc_path.exist?

        first = Leptris::XML.parse_html(doc_path.read).at_css("a[href]")
        return nil unless first

        subdir = File.dirname(href)
        subdir == "." ? first["href"] : "#{subdir}/#{first['href']}"
      end

      def wire_index_links(doc, top_level)
        doc.css("a").each do |a|
          href = a["href"]
          next unless href && top_level.key?(href)

          a["onclick"] =
            if File.basename(href).end_with?("_index.html")
              # Multi-section docs drive both frames; replace() avoids a
              # second history entry so back needs one click.
              "parent.index.location.replace('#{href}');" \
                "parent.info.location='#{top_level[href]}';return false;"
            else
              "parent.info.location='#{top_level[href]}'"
            end
        end
      end

      def inject_frameset_script(doc)
        # Idempotent: drop previously injected scripts first.
        doc.xpath("//script").each do |s|
          s.parent.remove_child(s) if s.text.include?("window.top")
        end
        head = doc.at_css("head") || doc.at_css("html").prepend_child("<head/>")
        script = doc.create_element("script")
        script.content = FRAMESET_JS
        head.add_child(script)
      end

      # -- document index files ------------------------------------------

      def add_target_attributes(top_level)
        top_level.each_key do |href|
          next unless File.basename(href).end_with?("_index.html")

          doc_path = @site_dir / href
          next unless doc_path.exist?

          doc = Leptris::XML.parse_html(doc_path.read)
          doc.css("a").each { |a| a["target"] = "info" }
          doc_path.write(doc.to_html)
        end
      end

      # -- section files ---------------------------------------------------

      def strip_metanorma_sidebar
        Dir.glob("#{@site_dir}/**/*_section_*.html").each do |file|
          content = File.read(file)
          updated = content
            .gsub(PREVIOUS_OVERRIDE_RE, "")
            .gsub(PREVIOUS_TOGGLE_RE, "")
            .sub("</head>", "#{CSS_OVERRIDE}</head>")
          File.write(file, updated) if updated != content
        end
      end
      # rubocop:enable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Layout/LineLength
    end
  end
end
