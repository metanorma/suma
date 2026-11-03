# frozen_string_literal: true

require "fileutils"
require "json"
require "pathname"
require "time"
require "yaml"

require "leptris"

module Suma
  module Delivery
    # Capture a part's independently rendered _site/ into a
    # stitcher-ready bundle (TCSC410303-2952 Stage B; port of
    # scripts/srl-build/srl_pack_bundle.py, fusing the iso_renamer.py +
    # align_parts.py layout normalization into one idempotent pass):
    #
    # 1. Normalize the flat document.xml.<N> render into a per-doc
    #    directory (<docid>_section_<N>.html …), rewriting intra-site
    #    hrefs to the new layout.
    # 2. Scan anchors (every id attribute) and unresolved-eref spans
    #    through Leptris.
    # 3. Determine the schemas the part owns from its collection.yml.
    # 4. Copy the per-doc dir, owned schema_docs/ dirs, and
    #    plain_schemas/ into <base>/parts/<part>/site/.
    # 5. Write <base>/parts/<part>/bundle.json for the stitcher.
    #
    # The per-doc directory name is parsed from the docid the corpus's
    # own bibdata declares (id tokens joined with underscores, prefixed
    # with the upcased docid type when the id carries no alphabetic
    # prefix token) — e.g. {type: "iso", id: "10303-41"} with year 2025
    # becomes ISO_10303-41_2025; {id: "DIS 10303-104"} becomes
    # DIS_10303-104_<year>. No stage heuristics: whatever the bibdata
    # says is used as-is.
    class Pack
      # The collection-processed suffix bibitemids carry
      # (`_ISO_<doc>_<doc>_<section>`); stripped before schema/entity
      # parsing.
      BIBITEMID_SUFFIX_RE = /_ISO_[A-Za-z0-9_-]+_ISO_[A-Za-z0-9_-]+_.+\z/
      BARE_BIBITEMID_RE = /\Aexpress_([a-z][a-z0-9_]*?)(?:\.(.+))?\z/
      SECTION_FILE_RE = /\Adocument(?:\.\d+)?\.xml\.(\d+)\.html\z/
      SECTION_ERR_FILE_RE = /\Adocument(?:\.\d+)?\.xml\.(\d+)\.err\.html\z/

      # align_parts.py's schema-link fixups, ported verbatim: every
      # schema_docs/plain_schemas href needs one more `../` once the
      # referencing file moves from _site/ into the per-doc directory
      # (the `../../` double-up fix plus the no-prefix forms).
      SCHEMA_LINK_FIXUPS = [
        [%r{href="\.\./\.\./schema_docs/([^/]+)/([^"]+)"},
         'href="../schema_docs/\1/\2"'],
        [%r{href="\.\./\.\./plain_schemas/(resources|modules)/([^/]+)/([^"]+)"},
         'href="../plain_schemas/\1/\2/\3"'],
        [%r{href="schema_docs/([^/]+)/([^"]+)"}, 'href="../schema_docs/\1/\2"'],
        [%r{href="plain_schemas/(resources|modules)/([^/]+)/([^"]+)"},
         'href="../plain_schemas/\1/\2/\3"'],
      ].freeze

      Result = Struct.new(:bundle_dir, :iso_name, keyword_init: true)

      attr_reader :base, :repo_root

      # A faithful port of an algorithmic pipeline: the metrics would
      # fragment it without making it clearer.
      # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/ParameterLists, Layout/LineLength
      def initialize(part:, srl_build_base:, repo_root:, skip_layout: false)
        @part = part
        @base = Pathname.new(File.expand_path(srl_build_base))
        @repo_root = Pathname.new(File.expand_path(repo_root))
        @skip_layout = skip_layout
      end

      def pack
        plan = load_plan
        entry = plan_entry(plan)
        site = check_worktree_site
        coll_path = part_collection_path(entry)
        identity = Plan.identity(coll_path.parent)

        Utils.log "Packing bundle for #{@part} (expected #{entry['iso_name']})"
        iso_dir = ensure_layout(site, identity)
        iso_name = iso_dir.basename.to_s
        note_iso_name_mismatch(entry, iso_name)

        anchors, unresolved_xrefs, sections = scan_sections(iso_dir)
        Utils.log "  sections:         #{sections.size}"
        Utils.log "  anchors (total):  #{anchors.values.sum(&:size)}"
        Utils.log "  unresolved xrefs: #{unresolved_xrefs.size}"

        schema_docs, plain_schema_files = owned_attachments(coll_path)
        Utils.log "  schemas attached: #{schema_docs.size}"

        bundle_dir = copy_artifacts(site, iso_dir, schema_docs)
        write_bundle(bundle_dir, plan, entry, identity, iso_name, sections,
                     schema_docs, plain_schema_files, anchors, unresolved_xrefs)
        Utils.log "Bundle ready: #{bundle_dir}"
        Result.new(bundle_dir: bundle_dir, iso_name: iso_name)
      end

      private

      # -- inputs -------------------------------------------------------

      def plan_path
        base / "plan.json"
      end

      def load_plan
        raise "Plan not found: #{plan_path} (run `suma delivery plan` first)" unless
          plan_path.exist?

        JSON.parse(plan_path.read)
      end

      def plan_entry(plan)
        entry = plan["parts"].find { |p| p["part_dir"] == @part }
        raise "Part '#{@part}' not in plan (#{plan_path})" unless entry

        entry
      end

      def worktree_site
        base / "wt" / @part / "_site"
      end

      def check_worktree_site
        raise "Worktree not found: #{worktree_site.parent}" unless
          worktree_site.parent.exist?
        raise "_site/ not found in #{worktree_site.parent} (build failed?)" unless
          worktree_site.exist?

        worktree_site
      end

      def part_collection_path(entry)
        repo_root / entry["source_dir"] / "collection.yml"
      end

      # -- Step A: layout normalization ---------------------------------

      def ensure_layout(site, identity)
        rendered = rendered_doc_name(identity)
        if (existing = find_part_subdir(site, identity, rendered))
          Utils.log "[skip] layout normalization already done"
          return existing
        end
        raise no_subdir_error(site) if @skip_layout

        mapping = build_file_mapping(site, rendered)
        rewrite_hrefs(site, mapping)
        move_files(site, mapping, site / rendered)
        apply_schema_fixups_dir(site / rendered)

        find_part_subdir(site, identity, rendered) || raise(no_subdir_error(site))
      end

      def no_subdir_error(site)
        "No <PREFIX>_<docid>_<year>/ subdir found in #{site} for #{@part}"
      end

      # The per-doc directory name, parsed from the bibdata-declared
      # docid: id tokens joined with underscores; when the id carries
      # no alphabetic prefix token, the upcased docid type prefixes it.
      def rendered_doc_name(identity)
        doc_id = identity["doc_id"].to_s
        tokens = doc_id.split
        body =
          if tokens.first&.match?(/\A[A-Za-z]+\z/)
            [tokens.first.upcase, *tokens.drop(1)].join("_")
          else
            [identity["docid_type"].to_s.upcase, doc_id].reject(&:empty?).join("_")
          end
        "#{body}_#{identity['year']}"
      end

      def find_part_subdir(site, identity, rendered)
        return nil unless site.exist?

        doc_key = identity["doc_id"].to_s.gsub(/\s+/, "_")
        year = identity["year"].to_s
        pattern = /\A[A-Z]+_#{Regexp.escape(doc_key)}_#{Regexp.escape(year)}\z/
        site.children.find do |child|
          child.directory? &&
            (pattern.match?(child.basename.to_s) ||
             child.basename.to_s == rendered)
        end
      end

      def build_file_mapping(site, rendered)
        mapping = {}
        site.children.sort.each do |file|
          next unless file.file?

          add_section_mapping(mapping, file.basename.to_s, rendered)
        end
        add_index_mapping(mapping, doc_index_file(site), rendered)
        mapping
      end

      # iso_renamer.py PHASE 2 naming: document.xml.<N>.html sections
      # and their .err.html siblings become
      # <rendered>_section_<N>[.err].html. The .xml and
      # .presentation.xml siblings stay at the site root (the Python
      # renamer touches *.html only).
      def add_section_mapping(mapping, name, rendered)
        if (m = SECTION_FILE_RE.match(name))
          mapping[name] = "#{rendered}_section_#{m[1]}.html"
        elsif (m = SECTION_ERR_FILE_RE.match(name))
          mapping[name] = "#{rendered}_section_#{m[1]}.err.html"
        end
        mapping
      end

      def add_index_mapping(mapping, index, rendered)
        return mapping unless index

        name = index.basename.to_s
        mapping[name] = "#{rendered}_index.html" unless name == "#{rendered}_index.html"
        mapping
      end

      # The top-level *_index.html produced by the single-document
      # render; renamed to <rendered>_index.html for the stitcher's
      # merged index and doc-level links.
      def doc_index_file(site)
        candidates = site.children.select do |child|
          child.file? && child.basename.to_s.end_with?("_index.html")
        end
        if candidates.size > 1
          names = candidates.map { |c| c.basename.to_s }.join(", ")
          raise "Multiple per-doc index files in #{site}: #{names}"
        end

        candidates.first
      end

      # iso_renamer.py PHASE 3 ported generically: swap every old
      # document/index filename href for its new name, preserving the
      # optional `./` prefix, any `#fragment`, and the quote style.
      def swap_hrefs(content, mapping)
        mapping.each do |old, new|
          content = content.gsub(
            /(href=["'])(\.\/)?(#{Regexp.escape(old)})(#[^"']*)?(["'])/,
          ) do
            m = Regexp.last_match
            "#{m[1]}#{m[2]}#{new}#{m[4]}#{m[5]}"
          end
        end
        content
      end

      def apply_schema_fixups(content)
        SCHEMA_LINK_FIXUPS.each do |pattern, replacement|
          content = content.gsub(pattern, replacement)
        end
        content
      end

      # Rewrites run Python-ordered: filename swaps over the flat top
      # level and schema_docs/ (iso_renamer PHASE 3), the files move
      # into the per-doc dir (PHASE 4), then align_parts.py's
      # schema-link fixups run on the moved files from their new depth.
      def rewrite_hrefs(site, mapping)
        swap_targets = (site.children.select do |c|
          c.file? && c.basename.to_s.end_with?(".html")
        end + Dir.glob("#{site}/schema_docs/**/*.html")
          .map { |p| Pathname.new(p) }).uniq.sort
        swap_targets.each do |file|
          rewrite_file(file) { |content| swap_hrefs(content, mapping) }
        end
      end

      def move_files(site, mapping, target_dir)
        FileUtils.mkdir_p(target_dir)
        mapping.each do |old, new|
          src = site / old
          FileUtils.mv(src, target_dir / new) if src.exist?
        end
      end

      def apply_schema_fixups_dir(dir)
        return unless dir.exist?

        dir.children.select { |c| c.file? && c.basename.to_s.end_with?(".html") }
          .sort.each do |file|
          rewrite_file(file) { |content| apply_schema_fixups(content) }
        end
      end

      def rewrite_file(file)
        content = file.read
        rewritten = yield content
        file.write(rewritten) if rewritten != content
      end

      # -- Step B: scan -------------------------------------------------

      def scan_sections(iso_dir)
        anchors = {}
        unresolved_xrefs = []
        sections = []
        html_files(iso_dir).each do |html_file|
          name = html_file.basename.to_s
          next if name.end_with?(".err.html")

          sections << name
          scan_html_file(html_file, name, anchors, unresolved_xrefs)
        end
        [anchors, unresolved_xrefs, sections]
      end

      def html_files(dir)
        dir.children.select { |c| c.file? && c.basename.to_s.end_with?(".html") }
          .sort
      end

      def scan_html_file(html_file, name, anchors, unresolved_xrefs)
        doc = Leptris::XML.parse_html(html_file.read)
        anchors[name] = doc.css("[id]").filter_map { |el| el["id"] }
          .reject(&:empty?).uniq.sort
        doc.css("span.unresolved-eref").each do |span|
          bibitemid = span["data-bibitemid"].to_s
          next if bibitemid.empty?

          schema, entity = parse_bibitemid(bibitemid)
          unresolved_xrefs << {
            "source_file" => name,
            "bibitemid" => bibitemid,
            "schema_ref" => schema,
            "entity_ref" => entity,
            "display_text" => span.text.strip,
            "citeas" => span["data-citeas"].to_s,
          }
        end
      end

      # srl_pack_bundle.py#parse_bibitemid: strip the collection-
      # processed `_ISO_<doc>_<doc>_<section>` suffix, then split an
      # `express_<schema>[.<entity>]` bibitemid.
      def parse_bibitemid(bibitemid)
        bare = bibitemid.gsub(BIBITEMID_SUFFIX_RE, "")
        m = BARE_BIBITEMID_RE.match(bare)
        m ? [m[1], m[2]] : [nil, nil]
      end

      # -- Step C: owned schema attachments -----------------------------

      def owned_attachments(coll_path)
        coll = YAML.safe_load_file(coll_path, aliases: true)
        part_dir = coll_path.parent
        schema_docs = []
        plain_schema_files = []
        Plan.walk_docrefs(coll["manifest"] || {}).each do |docref|
          ref = docref["fileref"]
          next unless ref.is_a?(String)

          collect_attachment(ref, part_dir, schema_docs, plain_schema_files)
        end
        [schema_docs.uniq.sort, plain_schema_files.uniq.sort]
      end

      def collect_attachment(ref, part_dir, schema_docs, plain_schema_files)
        if ref.end_with?(".exp")
          add_exp_attachment(ref, part_dir, schema_docs, plain_schema_files)
        elsif ref.end_with?(".html") && (m = %r{schema_docs/([^/]+)/}.match(ref))
          schema_docs << m[1]
        end
      end

      # .exp filerefs resolve to their source through Plan's
      # plain_schemas→schemas rule; the owned schema_docs dir is the
      # resolved file's parent, and the recorded plain_schemas path is
      # the same suffix under plain_schemas/. Filerefs that resolve
      # nowhere fall back to the Python's plain string parse.
      def add_exp_attachment(ref, part_dir, schema_docs, plain_schema_files)
        source = Plan.resolve_exp_source(ref, part_dir, repo_root)
        if source
          rel = source.relative_path_from(repo_root).to_s
          plain_rel = rel.sub(%r{\Aschemas/}, "plain_schemas/")
            .delete_prefix("plain_schemas/")
          plain_schema_files << plain_rel
          schema_docs << Pathname.new(plain_rel).parent.basename.to_s
        elsif (m = %r{plain_schemas/(.+\.exp)\z}.match(ref))
          plain_schema_files << m[1]
          schema_docs << Pathname.new(m[1]).parent.basename.to_s
        end
      end

      # -- Step D: copy into the bundle ---------------------------------

      def copy_artifacts(site, iso_dir, schema_docs)
        bundle_dir = base / "parts" / @part
        bundle_site = bundle_dir / "site"
        bundle_logs = bundle_dir / "logs"
        prior = bundle_dir / "bundle.json"
        previous = prior.exist? ? File.binread(prior) : nil

        FileUtils.rm_rf(bundle_dir)
        FileUtils.mkdir_p([bundle_site, bundle_logs])
        File.binwrite(bundle_dir / "bundle.json.previous", previous) if previous

        FileUtils.cp_r(iso_dir, bundle_site / iso_dir.basename)
        copy_owned_dirs(site / "schema_docs", bundle_site / "schema_docs",
                        schema_docs)
        plain = site / "plain_schemas"
        FileUtils.cp_r(plain, bundle_site / "plain_schemas") if plain.exist?

        [worktree_site.parent / "srl-build-#{@part}.log",
         worktree_site.parent / "collection-output.yaml"].each do |log|
          FileUtils.cp(log, bundle_logs / log.basename) if log.exist?
        end
        bundle_dir
      end

      def copy_owned_dirs(src_root, dst_root, owned)
        return unless src_root.exist?

        FileUtils.mkdir_p(dst_root)
        owned.each do |name|
          src = src_root / name
          FileUtils.cp_r(src, dst_root / name) if src.exist?
        end
      end

      # -- Step E: bundle.json -------------------------------------------

      # A faithful port: the record is one flat shape, assembled from
      # the plan entry, the identity, and the scan results.
      def write_bundle(bundle_dir, plan, entry, identity, iso_name, sections,
                       schema_docs, plain_schema_files, anchors, unresolved_xrefs)
        bundle = {
          "version" => 1,
          "part_dir" => entry["part_dir"],
          "iso_name" => iso_name,
          "source_dir" => entry["source_dir"],
          "build_timestamp" => Time.now.utc.iso8601,
          "build_commit" => plan["build_commit"],
          "doc_id" => identity["doc_id"],
          "year" => identity["year"],
          "doc_hash" => entry["doc_hash"],
          "deps_hash" => entry["deps_hash"],
          "input_files" => entry["input_files"],
          "exp_files" => entry["exp_files"],
          "sections" => sections,
          "schema_docs" => schema_docs,
          "plain_schemas" => plain_schema_files,
          "anchors" => anchors,
          "unresolved_xrefs" => unresolved_xrefs,
          "errors" => { "build_warnings" => [] },
        }
        File.write(bundle_dir / "bundle.json", JSON.pretty_generate(bundle))
      end

      def note_iso_name_mismatch(entry, iso_name)
        return if entry["iso_name"] == iso_name

        Utils.log "NOTE: plan iso_name=#{entry['iso_name'].inspect} but build " \
                  "produced #{iso_name.inspect} (stage prefix differs — using " \
                  "rendered value)"
      end
      # rubocop:enable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/ParameterLists, Layout/LineLength
    end
  end
end
