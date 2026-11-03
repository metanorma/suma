# frozen_string_literal: true

require "erb"
require "fileutils"
require "json"
require "pathname"
require "nokogiri"

module Suma
  module Srl
    # Merge independently rendered per-part sites into a single _site/,
    # rewriting each part's <span class="unresolved-eref"
    # data-bibitemid="…"> markers into cross-document <a href> elements
    # resolved through anchor, document and attachment registries built
    # from every bundle in the merge (TCSC410303-2952; port of
    # scripts/suma2srl/srl_stitch.py).
    #
    # Correctness model (design doc §4): cross-doc bibitemids carry
    # content-derived identifiers, and content-derived anchors are stable
    # across per-part and full-collection build modes, so a full merge
    # resolves every cross-doc reference; a broken record can only mean
    # the target's bundle is absent from the merge.
    #
    # The stitch is atomic: everything lands in <out>.tmp, and the swap
    # to <out> happens only after every step succeeded.
    class Stitcher
      # A faithful port of an algorithmic pipeline: the metrics would
      # fragment it without making it clearer.
      # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/ParameterLists, Layout/LineLength
      # `<scope>_ISO_<docid>_<year>_…`: the scope is the lowercase
      # identifier prefix. For docs published as IS the suffix is
      # `_ISO_10303-43_2025_…`; for DIS/TS a docstage prefix appears
      # between `_ISO_` and the docid.
      ANCHOR_SCOPE_RE = /\A([a-z][a-z0-9_]*(?:\.[a-z0-9_.]+)?)_ISO_(?:[A-Z]+_)?[A-Za-z0-9-]+_[0-9]+(?:_ISO_.+)?\z/

      # `express_<scope>_ISO_…`: schema/entity references.
      EXPRESS_BIBID_RE = /\Aexpress_([a-z][a-z0-9_]*(?:\.[a-z0-9_.]+)?)_ISO_/

      # `<schema>.html_ISO_…` / `<schema>.exp_ISO_…`: attachment refs.
      ATTACHMENT_BIBID_RE = /\A([a-z][a-z0-9_]*\.(?:html|exp))_ISO_/

      # Document-level bibitemid, both observed forms:
      # `ISO_<docid>_ISO_…` and the relaton-style `iso<docnum>-<part>_ISO_…`.
      DOC_LEVEL_BIBID_RE = /\A(?:ISO_(?<a>[A-Za-z0-9-]+)|iso(?<b>\d+-\d+))_ISO_/

      SHARED_DIRS = %w[schema_docs plain_schemas].freeze
      FRAME_ASSETS = %w[srl_index.html].freeze
      FRAME_ASSET_DIRS = %w[images sys].freeze

      Registries = Struct.new(:anchors, :docs, :attachments)
      Result = Struct.new(:resolved, :broken, :parts, keyword_init: true)

      # (a data-declaring initializer)
      def initialize(bundles_dir:, plan_path:, out_dir:, assets_dir: nil,
                     inject: nil, source_repo: "wg12-step",
                     source_commit: nil, source_branch: nil)
        @bundles_dir = Pathname.new(bundles_dir)
        @plan = JSON.parse(File.read(plan_path))
        @out_dir = Pathname.new(out_dir)
        @assets_dir = assets_dir && Pathname.new(assets_dir)
        @inject = inject
        @source_repo = source_repo
        @source_commit = source_commit
        @source_branch = source_branch
      end

      def stitch
        bundles = load_bundles
        raise "No bundles loaded — nothing to stitch" if bundles.empty?

        validate_injection(@inject, bundles) if @inject
        registries = build_registries(bundles)
        out_tmp = stage_merged_site(bundles)
        registries.attachments = build_attachment_registry(out_tmp)
        counts = patch_xrefs(out_tmp, registries)
        write_merged_index(out_tmp, bundles)
        copy_frame_assets(out_tmp)
        write_collection_errors(out_tmp, bundles, counts)
        write_build_info(out_tmp, bundles)
        write_stitch_summary(out_tmp, bundles, registries, counts)
        atomic_swap(out_tmp)
        Result.new(resolved: counts[:resolved], broken: counts[:broken],
                   parts: bundles.keys.sort)
      end

      private

      def load_bundles
        @plan["parts"].each_with_object({}) do |entry, h|
          part_dir = entry["part_dir"]
          path = @bundles_dir / part_dir / "bundle.json"
          h[part_dir] = JSON.parse(path.read) if path.exist?
        end
      end

      # -- registries --------------------------------------------------

      def build_registries(bundles)
        anchors = {}
        docs = {}
        bundles.each do |part_dir, bundle|
          iso_name = bundle["iso_name"]
          index_anchors(bundle).each do |file, anchor|
            scope = anchor_scope(anchor)
            anchors[scope] ||= [iso_name, file, anchor] if scope
          end
          entry = @plan["parts"].find { |p| p["part_dir"] == part_dir }
          docs["ISO_#{entry['doc_id']}"] = iso_name if entry
        end
        Registries.new(anchors, docs, {})
      end

      def index_anchors(bundle)
        bundle["anchors"].flat_map do |file, list|
          list.map { |a| [file, a] }
        end
      end

      def anchor_scope(anchor)
        ANCHOR_SCOPE_RE.match(anchor)&.[](1)
      end

      def build_attachment_registry(out_dir)
        registry = {}
        schema_docs = out_dir / "schema_docs"
        schema_docs.glob("doc_*.html").sort.each do |html|
          stem = html.basename.to_s.delete_suffix(".html")
          key = "#{stem.delete_prefix('doc_')}.html"
          registry[key] = [nil, html.relative_path_from(out_dir).to_s, nil]
        end
        plain = out_dir / "plain_schemas"
        plain.glob("**/*.exp").sort.each do |exp|
          registry[exp.basename.to_s] =
            [nil, exp.relative_path_from(out_dir).to_s, nil]
        end
        registry
      end

      def resolve_bibitemid(bibitemid, registries)
        return nil if bibitemid.nil? || bibitemid.empty?

        if (m = EXPRESS_BIBID_RE.match(bibitemid))
          return registries.anchors[m[1]]
        end
        return registries.attachments[m[1]] if (m = ATTACHMENT_BIBID_RE.match(bibitemid))

        doc_level_target(bibitemid, registries)
      end

      def doc_level_target(bibitemid, registries)
        m = DOC_LEVEL_BIBID_RE.match(bibitemid) or return nil
        docid_key = m[:a] ? "ISO_#{m[:a]}" : "ISO_#{m[:b]}"
        iso = registries.docs[docid_key] or return nil
        [iso, "#{iso}_index.html", nil]
      end

      # -- merge + rewrite ----------------------------------------------

      def stage_merged_site(bundles)
        out_tmp = out_tmp_dir
        FileUtils.rm_rf(out_tmp)
        FileUtils.mkdir_p(out_tmp)
        bundles.each do |part_dir, bundle|
          merge_bundle(part_dir, bundle, out_tmp)
        end
        out_tmp
      end

      def merge_bundle(part_dir, bundle, out_tmp)
        src_site = @bundles_dir / part_dir / "site"
        iso_dir = src_site / bundle["iso_name"]
        FileUtils.cp_r(iso_dir, out_tmp / bundle["iso_name"]) if iso_dir.exist?
        SHARED_DIRS.each do |shared|
          src = src_site / shared
          merge_tree(src, out_tmp / shared) if src.exist?
        end
      end

      def patch_xrefs(out_dir, registries)
        resolved = 0
        broken_records = []
        html_files(out_dir).each do |html_file|
          dirty = patch_file_xrefs(html_file, out_dir, registries) do |record|
            broken_records << record
          end
          resolved += dirty
        end
        write_broken_xrefs(out_dir, broken_records)
        { resolved: resolved, broken: broken_records.size }
      end

      # Returns the number of resolved spans in this file; broken spans
      # are yielded as audit records.
      def patch_file_xrefs(html_file, out_dir, registries)
        owning_iso = infer_owning_iso(html_file, out_dir)
        doc = Nokogiri::HTML(html_file.read)
        resolved = 0
        doc.css("span.unresolved-eref").each do |span|
          target = resolve_bibitemid(span["data-bibitemid"].to_s, registries)
          if target.nil?
            yield broken_record(html_file, out_dir, span)
            next
          end
          span.replace(resolved_link(owning_iso, target, span.text))
          resolved += 1
        end
        html_file.write(doc.to_html) if resolved.positive?
        resolved
      end

      def broken_record(html_file, out_dir, span)
        {
          "source_file" => html_file.relative_path_from(out_dir).to_s,
          "bibitemid" => span["data-bibitemid"].to_s,
          "display_text" => span.text.strip,
        }
      end

      def resolved_link(owning_iso, target, text)
        target_iso, target_file, target_anchor = target
        href = link_href(owning_iso, target_iso, target_file)
        href = "#{href}##{target_anchor}" if target_anchor
        "<a href=\"#{ERB::Util.html_escape(href)}\" " \
          "class=\"resolved-eref\">#{ERB::Util.html_escape(text)}</a>"
      end

      def link_href(owning_iso, target_iso, target_file)
        return "../#{target_file}" if target_iso.nil?
        return target_file.to_s if owning_iso == target_iso

        "../#{target_iso}/#{target_file}"
      end

      def html_files(out_dir)
        Dir.glob("#{out_dir}/**/*.html")
          .reject { |f| f.end_with?(".err.html") }
          .map { |f| Pathname.new(f) }
      end

      def infer_owning_iso(html_file, out_dir)
        first = html_file.relative_path_from(out_dir).to_s
          .split(File::SEPARATOR)[0].to_s
        first.start_with?("ISO_") ? first : ""
      end

      def merge_tree(src, dst)
        FileUtils.mkdir_p(dst)
        src.each_child do |entry|
          target = dst / entry.basename
          next if target.exist? && entry.file?

          if entry.directory?
            merge_tree(entry,
                       target)
          else
            FileUtils.cp(entry, target)
          end
        end
      end

      # -- synthesized artifacts ----------------------------------------

      def write_merged_index(out_dir, bundles)
        rows = @plan["parts"].filter_map do |entry|
          bundle = bundles[entry["part_dir"]] or next
          iso_name = bundle["iso_name"]
          %(<li><a href="#{iso_name}/#{iso_name}_index.html">#{iso_name}</a></li>)
        end
        html = <<~HTML
          <!DOCTYPE html>
          <html><head>
          <meta charset="utf-8"/>
          <title>STEP Resources Library</title>
          </head><body>
          <h1>STEP Resources Library</h1>
          <ul>
          #{rows.join("\n")}
          </ul>
          </body></html>
        HTML
        (out_dir / "index.html").write(html)
      end

      def copy_frame_assets(out_dir)
        return unless @assets_dir&.exist?

        FRAME_ASSETS.each do |name|
          src = @assets_dir / name
          FileUtils.cp(src, out_dir / name) if src.exist?
        end
        FRAME_ASSET_DIRS.each do |name|
          src = @assets_dir / name
          next unless src.directory?

          dst = out_dir / name
          FileUtils.rm_rf(dst)
          FileUtils.cp_r(src, dst)
        end
      end

      def write_collection_errors(out_dir, bundles, counts)
        entries = JSON.parse((out_dir / "broken_xrefs.json").read)["entries"]
        warnings = bundles.values.flat_map do |bundle|
          bundle.dig("errors", "build_warnings").to_a
            .map { |w| [bundle["iso_name"], w] }
        end
        rows = entries.map { |e| xref_error_row(e) } +
          warnings.map { |iso, warn| error_row(iso, "Build warning", warn) }
        html = error_page_html(rows, counts, warnings.size)
        (out_dir / "collection-errors.html").write(html)
      end

      def xref_error_row(entry)
        iso = entry["source_file"].to_s.split("/", 2)[0].to_s
        detail = "bibitemid=#{entry['bibitemid'].to_s[0, 140]} " \
                 "text=#{entry['display_text'].to_s.inspect}"
        error_row(iso, "Unresolved cross-doc xref", detail)
      end

      def error_row(iso, klass, detail)
        cell = iso.empty? ? "&nbsp;" : ERB::Util.html_escape(iso)
        "<tr><td>#{cell}</td><td>#{klass}</td>" \
          "<td><code>#{ERB::Util.html_escape(detail)}</code></td></tr>"
      end

      def error_page_html(rows, counts, warning_count)
        <<~HTML
          <!DOCTYPE html>
          <html><head><meta charset="utf-8"/><title>SRL Collection Errors</title>
          <style>body{font-family:sans-serif;margin:1em}table{border-collapse:collapse;width:100%}
          th,td{border:1px solid #ccc;padding:.3em .6em;text-align:left;vertical-align:top}
          th{background:#f0f0f0}code{word-break:break-all}</style>
          </head><body>
          <h1>SRL Collection Errors</h1>
          <p>Aggregated from per-bundle build warnings and unresolved cross-document references.</p>
          <p><strong>#{counts[:resolved]}</strong> cross-doc xrefs resolved, <strong>#{counts[:broken]}</strong> unresolved,
             <strong>#{warning_count}</strong> build warnings.</p>
          <table>
          <tr><th>Document</th><th>Class</th><th>Detail</th></tr>
          #{rows.join("\n")}
          </table>
          </body></html>
        HTML
      end

      def write_build_info(out_dir, bundles)
        info = {
          "source_repo" => @source_repo,
          "source_commit" => @source_commit || @plan["build_commit"] || "unknown",
          "source_branch" => @source_branch || "unknown",
          "build_timestamp" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
          "build_result" => "SUCCESSFUL",
          "parts_count" => bundles.size,
          "stitcher" => "suma srl stitch (TCSC410303-2952)",
        }
        (out_dir / "build-info.json").write(JSON.pretty_generate(info))
      end

      def write_stitch_summary(out_dir, bundles, registries, counts)
        summary = {
          "version" => 1,
          "stitch_timestamp" => Time.now.utc.iso8601,
          "build_commit" => @plan["build_commit"],
          "inject_target" => @inject,
          "parts_stitched" => bundles.keys.sort,
          "anchor_registry_size" => registries.anchors.size,
          "doc_registry_size" => registries.docs.size,
          "xrefs_resolved" => counts[:resolved],
          "xrefs_broken" => counts[:broken],
        }
        (out_dir / "stitch_summary.json").write(JSON.pretty_generate(summary))
      end

      def write_broken_xrefs(out_dir, broken_records)
        (out_dir / "broken_xrefs.json").write(JSON.pretty_generate({
                                                                     "version" => 1,
                                                                     "count" => broken_records.size,
                                                                     "entries" => broken_records,
                                                                   }))
      end

      def out_tmp_dir
        @out_dir.parent / "#{@out_dir.basename}.tmp"
      end

      def atomic_swap(out_tmp)
        old = @out_dir.parent / "#{@out_dir.basename}.old"
        FileUtils.rm_rf(old)
        @out_dir.exist? and FileUtils.mv(@out_dir, old)
        FileUtils.mv(out_tmp, @out_dir)
        FileUtils.rm_rf(old)
      end

      # -- inject invariants (design doc §8) ----------------------------

      def validate_injection(part_dir, bundles)
        new_bundle = bundles[part_dir] or
          raise "inject #{part_dir}: no current bundle loaded"
        prev_bundle = prev_bundle_for(part_dir)
        failures = injection_failures(part_dir, bundles, prev_bundle,
                                      new_bundle)
        raise "inject #{part_dir} rejected:\n#{failures.join("\n")}" if failures.any?
      end

      def prev_bundle_for(part_dir)
        path = @bundles_dir / part_dir / "bundle.json.previous"
        path.exist? ? JSON.parse(path.read) : nil
      end

      def injection_failures(part_dir, bundles, prev_bundle,
new_bundle)
        failures = []
        if prev_bundle && new_bundle["iso_name"] != prev_bundle["iso_name"]
          failures << identity_failure(
            prev_bundle, new_bundle
          )
        end
        failures.concat(anchor_regression_failure(part_dir, bundles,
                                                  prev_bundle, new_bundle))
        failures.concat(unresolvable_reference_failure(
                          bundles, new_bundle
                        ))
        failures
      end

      def identity_failure(prev_bundle, new_bundle)
        "identity: iso_name changed from #{prev_bundle['iso_name'].inspect} " \
          "to #{new_bundle['iso_name'].inspect}; a full re-stitch is required."
      end

      def anchor_regression_failure(part_dir, bundles, prev_bundle, new_bundle)
        return [] unless prev_bundle

        consumed = consumed_scopes(part_dir, bundles, prev_bundle)
        dropped = consumed - bundle_scopes(new_bundle)
        return [] if dropped.empty?

        ["anchor regression: #{dropped.size} scope(s) consumed by other parts " \
         "are missing from the new bundle. Examples: #{dropped.sort.first(5)}"]
      end

      def consumed_scopes(part_dir, bundles, prev_bundle)
        prev_scopes = bundle_scopes(prev_bundle)
        bundles.filter_map do |other, other_bundle|
          next if other == part_dir

          other_bundle["unresolved_xrefs"].to_a
            .map { |ux| scope_from_bibitemid(ux["bibitemid"].to_s) }
            .select { |scope| scope && prev_scopes.include?(scope) }
        end.flatten.uniq
      end

      def unresolvable_reference_failure(bundles, new_bundle)
        all_scopes = bundles.values.flat_map { |b| bundle_scopes(b) }.uniq
        anomalies = new_bundle["unresolved_xrefs"].to_a.filter_map do |ux|
          unresolvable_scope(ux, all_scopes)
        end
        return [] if anomalies.empty?

        sample = anomalies.first(3).map { |u| u["bibitemid"].to_s[0, 80] }
        ["unresolvable new references: #{anomalies.size} bibitemid(s) target " \
         "schemas not owned by any SRL part. Examples: #{sample}"]
      end

      def unresolvable_scope(unresolved, all_scopes)
        m = EXPRESS_BIBID_RE.match(unresolved["bibitemid"].to_s) or return nil
        scope = m[1]
        return nil if all_scopes.include?(scope)

        schema = scope.split(".", 2)[0]
        return nil if all_scopes.any? { |s| s.split(".", 2)[0] == schema }

        unresolved
      end

      def bundle_scopes(bundle)
        (bundle["anchors"] || {}).values.flatten
          .filter_map { |a| anchor_scope(a) }.uniq
      end

      def scope_from_bibitemid(bibitemid)
        EXPRESS_BIBID_RE.match(bibitemid)&.[](1)
      end
      # rubocop:enable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/ParameterLists, Layout/LineLength
    end
  end
end
