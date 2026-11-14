# frozen_string_literal: true

require "json"
require "yaml"
require "fileutils"
require "metanorma"

module Suma
  class StagedCollectionBuilder
    # The code the staged builder's child processes run. Children are
    # spawned as `ruby -e 'require "suma"; Worker.run'` with the mode and
    # paths on ARGV and render options JSON-encoded on STDIN. All
    # worker logic lives here as real, spec-testable methods: the previous
    # implementation embedded this code as generated script strings, which
    # is unauditable and shipped dead code once (suma#166 - an
    # interpolating heredoc silently ate the regex anchors in the alias
    # matchers, so the artefact aliases never landed and reinflate failed
    # with "no stored artefact").
    module Worker
      # One batch stage's spawn parameters, threaded through the batch
      # render methods.
      BatchContext =
        Struct.new(:config_dir, :batch_count, :store_dir, :out_dir,
                   :no_valid)

      module_function

      # Entry. ARGV = ["stage", manifest_path, store_dir, id_slug] with
      # render options on STDIN (sequential stage: render one member and
      # alias its artefacts); ARGV = ["batch", config_dir, batch_count,
      # store_dir, out_dir, no_valid] (batch stage: claim and render
      # batch files until none remain); ARGV = ["render", manifest_path]
      # with options on STDIN (plain render, no aliasing - reinflate).
      def run(argv = ARGV)
        case mode = argv.shift
        when "stage" then stage(*argv)
        when "batch" then batch(*argv)
        when "render" then render_only(*argv)
        else abort("[suma staged worker] unknown mode #{mode.inspect}")
        end
      end

      # Sequential stage: one fresh process per member, so peak memory
      # stays at one member (metanorma/metanorma#576).
      def stage(manifest_path, store_dir, id_slug)
        collection = render_with_options(manifest_path)
        alias_artifacts(collection, id_slug, store_dir)
      end

      # Plain render (reinflate): no store aliasing - the reinflate pass
      # consumes the store, it does not extend it.
      def render_only(manifest_path)
        render_with_options(manifest_path)
      end

      # The render options arrive from the parent over STDIN as JSON (not
      # Marshal: deserializing a stream is rb/unsafe-deserialization, and
      # the payload is plain strings, booleans, arrays, and nested hashes
      # - JSON expresses it exactly, with symbols restored below).
      def render_with_options(manifest_path)
        Metanorma::Collection.parse(manifest_path)
          .render(load_options($stdin.read))
      end

      # Parent side: symbols and hash keys become strings for the wire.
      def dump_options(opts)
        JSON.generate(dump_value(opts))
      end

      # Child side: restore symbol top-level keys, symbol :format values,
      # and the nested :compile hash.
      def load_options(json)
        opts = JSON.parse(json).to_h { |k, v| [k.to_sym, v] }
        opts[:format] = opts[:format].map(&:to_sym) if opts[:format]
        if opts[:compile]
          opts[:compile] = opts[:compile].to_h do |k, v|
            [k.to_sym, v]
          end
        end
        opts
      end

      def dump_value(value)
        case value
        when Hash then value.to_h { |k, v| [k.to_s, dump_value(v)] }
        when Array then value.map { |v| dump_value(v) }
        when Symbol then value.to_s
        else value
        end
      end

      # Batch stage: claim one batch file at a time through O_EXCL
      # markers, so N concurrent children partition the batches without a
      # coordinator; a child with no batches left exits and hands its
      # memory back to the OS. Exits 1 when it could claim nothing while
      # batches were announced (nothing was rendered).
      def batch(config_dir, batch_count, store_dir, out_dir, no_valid)
        ctx = BatchContext.new(config_dir, Integer(batch_count), store_dir,
                               out_dir, no_valid)
        claimed = 0
        while (idx = claim_batch(ctx.config_dir, ctx.batch_count))
          render_batch(ctx, idx)
          claimed += 1
        end
        exit 1 if claimed.zero? && ctx.batch_count.positive?
      end

      def render_batch(ctx, idx)
        # The batch file is written by this builder's own write_batch_bins
        # in the same process tree - trusted, same-toolchain data, JSON-
        # encoded member manifests.
        manifests = JSON.parse(File.read(batch_file(ctx.config_dir, idx)))
        manifests.each_with_index do |manifest, pos|
          render_batch_member(ctx, idx, pos, manifest)
        end
      end

      def render_batch_member(ctx, idx, pos, manifest)
        one_path = File.join(ctx.config_dir, "._suma_staged_b#{idx}_#{pos}.yml")
        out = File.join(ctx.out_dir, "._staged_out_b#{idx}_#{pos}")
        started = Time.now
        render_and_alias(render_member(one_path, ctx, out), manifest, ctx)
        log_batch_ok(ctx, idx, pos, started)
      ensure
        FileUtils.rm_f(one_path)
        FileUtils.rm_rf(out)
        GC.start
      end

      def render_and_alias(collection, manifest, ctx)
        alias_artifacts(collection, slug(member_identifier(manifest)),
                        ctx.store_dir)
      end

      def render_member(manifest_path, ctx, out)
        compile = { install_fonts: false }
        compile[:novalid] = true if ctx.no_valid == "1"
        collection = Metanorma::Collection.parse(manifest_path)
        collection.render(
          format: [:xml], output_folder: out,
          preserve_unresolved: true, artifact_store_dir: ctx.store_dir,
          compile: compile
        )
        collection
      end

      def log_batch_ok(ctx, idx, pos, started)
        warn format(
          "[staged worker %<pid>d] batch %<idx>d/%<count>d member " \
          "%<pos>d OK (%<seconds>d s)",
          pid: Process.pid, idx: idx + 1, count: ctx.batch_count, pos: pos,
          seconds: Time.now - started
        )
      end

      # The artefact aliasing both stage paths perform after a member's
      # store write (metanorma/suma#204): the store keys on the rendered
      # document's own docid slug, while the parent reinflates and the
      # warm-skip look up by the docref identifier. Without these copies a
      # render banks entries the lookups can never find - the sequential
      # stage never warm-skipped for exactly this reason.
      def alias_artifacts(collection, id_slug, store_dir)
        alias_from_bibdatas(collection, id_slug, store_dir)
        alias_from_identifier_aliases(identifier_aliases(collection),
                                      store_dir)
      end

      # Alias from the collection's own bibdata keys: they are the docids
      # this render stored under. A produced-files delta is not safe here
      # - with concurrent workers another child's render lands in the
      # shared store mid-flight, and a delta would alias other members'
      # documents under this docref (suma#167). bibdatas is empty for
      # corpus manifests (suma#181) - the identifier_aliases below drive
      # the aliasing in that case.
      def alias_from_bibdatas(collection, id_slug, store_dir)
        return if id_slug.empty?

        collection.bibdatas&.each_key do |key|
          src = slug(key)
          next if src.empty? || src == id_slug

          copy_store_entries(src, id_slug, store_dir)
        end
      end

      # identifier_aliases maps raw identifier -> resolved docid; alias
      # the resolved-docid entries under the raw identifier's slug.
      def alias_from_identifier_aliases(aliases, store_dir)
        aliases.each do |original, resolved|
          src = slug(resolved)
          dst = slug(original)
          next if src.empty? || dst.empty? || src == dst

          copy_store_entries(src, dst, store_dir)
        end
      end

      def copy_store_entries(src, dst, store_dir)
        Dir[File.join(store_dir, "#{src}.*.semantic.xml")].each do |f|
          FileUtils.cp(f, f.sub(%r{/#{Regexp.escape(src)}\.}, "/#{dst}."))
        end
      end

      def identifier_aliases(collection)
        collection.manifest.identifier_aliases || {}
      rescue NoMethodError
        {}
      end

      def member_identifier(manifest)
        manifest.dig("manifest", "manifest", 0, "docref", 0, "identifier")
      end

      def claim_batch(config_dir, count)
        (0...count).find do |i|
          try_claim(File.join(config_dir, "._suma_batch_#{i}.claim"))
        end
      end

      # O_EXCL create: succeeds for exactly one child, fails with
      # EEXIST for everyone else - the claim.
      def try_claim(path)
        File.open(path, File::RDWR | File::CREAT | File::EXCL) do |claim|
          claim.write("1")
        end
        true
      rescue Errno::EEXIST
        false
      end

      def batch_file(config_dir, idx)
        File.join(config_dir, "._suma_batch_#{idx}.bin")
      end

      # Mirrors the store's filename slug (metanorma ArtifactStore#slug).
      # The \A/\z anchors are load-bearing: they trim leading/trailing
      # dashes only, and losing them in generated text was the suma#166
      # defect.
      def slug(value)
        value.to_s.gsub(/[^A-Za-z0-9._-]+/, "-")
          .gsub(/-{2,}/, "-").gsub(/\A-|-\z/, "")
      end
    end
  end
end
