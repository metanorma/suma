# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "yaml"

module Suma
  module Delivery
    # Enumerates the parts of a stitched delivery from the collection
    # manifest and writes plan.json: one entry per docref with the part's
    # identity, input inventory, and content hashes. Drives the
    # per-document stitcher pipeline (TCSC410303-2952 Stage A).
    class Plan
      DEFAULT_COLLECTION = "collection-resources.yml"

      attr_reader :repo_root, :collection, :out_path

      def initialize(repo_root:, out:, collection: DEFAULT_COLLECTION)
        @repo_root = Pathname.new(File.expand_path(repo_root))
        @collection = collection
        @out_path = Pathname.new(out)
      end

      def generate
        docrefs = manifest_docrefs(load_collection_manifest)
        unless docrefs.any?
          raise "No manifest.docref entries in #{collection_path}"
        end

        parts = plan_parts(docrefs)
        plan = build_plan(parts)
        write_plan(plan)
        plan
      end

      private

      def collection_path
        repo_root + collection
      end

      def load_collection_manifest
        YAML.safe_load_file(collection_path, aliases: true)
      end

      def manifest_docrefs(manifest)
        node = manifest.dig("manifest", "docref")
        [node].compact.flatten
      end

      def plan_parts(docrefs)
        docrefs.filter_map do |ref|
          next unless ref.is_a?(Hash) && ref["file"]

          part_collection = repo_root + ref["file"]
          unless part_collection.exist?
            Utils.log "WARN: docref not found: #{part_collection}"
            next
          end
          analyze_part(part_collection.parent)
        end
      end

      def build_plan(parts)
        {
          "version" => 1,
          "source_collection" => collection,
          "build_commit" => build_commit,
          "build_timestamp" => Time.now.utc.iso8601,
          "parts_count" => parts.size,
          "parts" => parts,
        }
      end

      def analyze_part(part_dir)
        coll = YAML.safe_load_file(File.join(part_dir, "collection.yml"),
                                   aliases: true)
        bibdata = coll["bibdata"] || {}
        doc_id = fetch_doc_id(bibdata, part_dir)
        year = derive_year(part_dir, bibdata)
        exp_files = exp_sources(part_dir, coll)
        inputs = inventory(part_dir) + exp_files

        part_identity(part_dir, doc_id,
                      year).merge(part_hashes(inputs, exp_files))
      end

      def part_identity(part_dir, doc_id, year)
        {
          "part_dir" => part_dir.basename.to_s,
          "source_dir" => part_dir.relative_path_from(repo_root).to_s,
          "iso_name" => "ISO_#{doc_id}_#{year}",
          "doc_id" => doc_id,
          "year" => year,
        }
      end

      def part_hashes(inputs, exp_files)
        {
          "doc_hash" => "sha256:#{sha256_files(inputs)}",
          "deps_hash" => "sha256:#{sha256_files(exp_files)}",
          "input_files" => inputs.map { |p| rel_or_abs(p) },
          "exp_files" => exp_files.map { |p| rel_or_abs(p) },
        }
      end

      def fetch_doc_id(bibdata, part_dir)
        node = bibdata["docid"] || {}
        node = node.first if node.is_a?(Array)
        id = node && node["id"]
        id || part_dir.basename.to_s.delete_prefix("iso-")
      end

      def derive_year(part_dir, bibdata)
        adoc = File.join(part_dir, "document.adoc")
        return copyright_from_bibdata(bibdata) unless File.exist?(adoc)

        File.foreach(adoc) do |line|
          if (m = line.match(/\A:copyright-year:\s*(\d+)/))
            return m[1]
          end
        end
        copyright_from_bibdata(bibdata)
      end

      def copyright_from_bibdata(bibdata)
        from = bibdata.dig("copyright", "from")
        from ? from.to_s : "0000"
      end

      def inventory(part_dir)
        inputs = [File.join(part_dir, "collection.yml")]
        adoc = File.join(part_dir, "document.adoc")
        inputs << adoc if File.exist?(adoc)
        inputs += section_files(part_dir)
        cover = File.join(part_dir, "cover.html")
        inputs << cover if File.exist?(cover)
        inputs
      end

      def section_files(part_dir)
        sections = File.join(part_dir, "sections")
        return [] unless File.directory?(sections)

        Dir.glob(File.join(sections, "**/*")).select { |p| File.file?(p) }
          .sort.map { |p| Pathname.new(p) }
      end

      def exp_sources(part_dir, coll)
        entries = walk_docrefs(coll["manifest"] || {})
        entries.filter_map do |entry|
          ref = entry["fileref"]
          next unless ref.is_a?(String) && ref.end_with?(".exp")

          resolve_exp_source(ref, part_dir)
        end
      end

      def walk_docrefs(node, acc = [])
        return acc unless node.is_a?(Hash)

        docref = node["docref"]
        [docref].compact.flatten.each do |entry|
          next unless entry.is_a?(Hash)

          acc << entry
          walk_docrefs(entry, acc)
        end
        acc
      end

      # collection.yml filerefs point at plain_schemas/ (build-time
      # output); the source lives at schemas/ under the same suffix.
      def resolve_exp_source(fileref, part_dir)
        raw = (part_dir + fileref).expand_path
        return raw if raw.exist? && under_repo?(raw)

        candidate = Pathname.new(raw.to_s.sub("/plain_schemas/", "/schemas/"))
        candidate.exist? ? candidate : nil
      end

      def sha256_files(paths)
        h = Digest::SHA256.new
        paths.each { |path| hash_one_file(h, path) }
        h.hexdigest
      end

      def hash_one_file(hash, path)
        hash.update(rel_or_abs(path))
        hash.update("\0")
        File.open(path, "rb") do |f|
          while (chunk = f.read(65_536))
            hash.update(chunk)
          end
        end
        hash.update("\0\0")
      end

      def rel_or_abs(path)
        path = Pathname.new(path)
        under_repo?(path) ? path.relative_path_from(repo_root).to_s : path.to_s
      end

      def under_repo?(path)
        path.expand_path.to_s.start_with?("#{repo_root.expand_path}/")
      end

      def build_commit
        @build_commit ||=
          begin
            git("rev-parse", "HEAD")
          rescue StandardError
            "unknown"
          end
      end

      def git(*args)
        out, err, status = Open3.capture3("git", "-C", repo_root.to_s, *args)
        raise "git #{args.first} failed: #{err}" unless status.success?

        out.strip
      end

      def write_plan(plan)
        out_path.parent.mkpath
        File.write(out_path, JSON.pretty_generate(plan))
        Utils.log "plan.json written: #{out_path} " \
                  "(parts: #{plan['parts_count']}, " \
                  "commit: #{plan['build_commit']})"
      end
    end
  end
end
