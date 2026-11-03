# frozen_string_literal: true

require "json"
require "thor"

module Suma
  module Cli
    # Stitched-delivery commands (introduced for TCSC410303-2952): enumerate
    # parts, merge independently rendered per-part bundles into one stitched
    # site, resolve their unresolved cross-document references, and verify
    # the result. Artifact names (SRL/SMRL/...) are corpus-side; this
    # surface is name-neutral and driven by whatever manifests the caller
    # points it at.
    class Delivery < Thor
      desc "verify SITE_DIR",
           "Verify every link in the stitched site resolves: cross-file " \
           "hrefs to files, fragments to anchors in their target. The " \
           "production gate is zero broken links; exits 1 on any break. " \
           "Intra-file fragment hrefs are reported but do not fail."
      option :out, type: :string,
                   desc: "Also write the report as JSON to this path"
      option :no_fragments, type: :boolean, default: false,
                            desc: "Skip fragment checking (file existence only)"

      def verify(site_dir)
        result = Suma::Delivery::SiteVerifier.new(site_dir,
                                                  **verify_options).verify
        log_verify(result)
        raise "broken links found (#{result.broken_count})" unless
          result.broken_count.zero?
      end

      desc "stitch BUNDLES_DIR",
           "Merge per-part bundles (each bundle.json + site/) into one " \
           "_site/, resolving every unresolved-eref span through the " \
           "anchor/doc/attachment registries; writes the audit records " \
           "and the merged index"
      option :plan, type: :string, required: true,
                    desc: "plan.json (part inventory: part_dir + doc_id " \
                          "per part)"
      option :out, type: :string, required: true,
                   desc: "Output merged _site directory"
      option :assets, type: :string,
                      desc: "Directory with srl_index.html, images/, sys/ " \
                            "frame-navigation assets"
      option :inject, type: :string, banner: "PART_DIR",
                      desc: "Rebuilding one part: validate the " \
                            "link-signature invariants before stitching"
      option :source_commit, type: :string,
                             desc: "Commit SHA recorded in build-info.json"
      option :source_branch, type: :string,
                             desc: "Branch recorded in build-info.json"

      def stitch(bundles_dir)
        result = Suma::Delivery::Stitcher.new(**stitch_options(bundles_dir)).stitch
        Utils.log "Stitched #{result.parts.size} into #{options[:out]}: " \
                  "#{result.resolved} ok, #{result.broken} broken"
      end

      desc "plan", "Enumerate parts from the collection manifest and " \
                   "write plan.json for the stitcher: per-part identity " \
                   "(iso_name, doc_id, year), input inventory, and " \
                   "doc/deps content hashes"
      option :collection, type: :string, default: "collection-resources.yml",
                          desc: "Collection manifest listing one docref per " \
                                "part, relative to --repo-root"
      option :repo_root, type: :string, default: ".",
                         desc: "Repository root"
      option :out, type: :string, required: true,
                   desc: "Output plan.json path"

      def plan
        result = Suma::Delivery::Plan.new(**plan_options).generate
        Utils.log "Planned #{result['parts_count']} parts " \
                  "from #{result['source_collection']}"
      end

      desc "frame-nav SITE_DIR", "Post-process a stitched site for " \
                                 "frame navigation: strip the index chrome, " \
                                 "build the top-level index, wire onclick " \
                                 "index links, inject the frameset script, " \
                                 "and add target attributes"
      def frame_nav(site_dir)
        Suma::Delivery::FrameNav.new(site_dir).process
        Utils.log "Frame navigation applied to #{site_dir}"
      end

      private

      def verify_options
        { check_fragments: !options[:no_fragments] }
      end

      def log_verify(result)
        report = result.report
        write_report(report) if options[:out]
        Utils.log "Links: #{report['total_links']} total, " \
                  "#{report['broken_links'].size} broken; " \
                  "fragments: #{report['total_fragments']} total, " \
                  "#{report['broken_fragments'].size} broken; " \
                  "#{report['cross_document_links']} cross-document"
      end

      def write_report(report)
        File.write(options[:out], JSON.pretty_generate(report))
      end

      def stitch_options(bundles_dir)
        {
          bundles_dir: bundles_dir,
          plan_path: options[:plan],
          out_dir: options[:out],
          assets_dir: options[:assets],
          inject: options[:inject],
          source_commit: options[:source_commit],
          source_branch: options[:source_branch],
        }
      end

      def plan_options
        {
          repo_root: options[:repo_root],
          collection: options[:collection],
          out: options[:out],
        }
      end
    end
  end
end
