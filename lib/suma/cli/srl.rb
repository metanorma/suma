# frozen_string_literal: true

require "json"
require "thor"

module Suma
  module Cli
    # SRL delivery commands (TCSC410303-2952): merge independently
    # rendered per-part bundles into one stitched site with resolved
    # cross-document references.
    class Srl < Thor
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
        result = Suma::Srl::SiteVerifier.new(site_dir, **verify_options).verify
        log_verify(result)
        raise "broken links found (#{result.broken_count})" unless result.broken_count.zero?
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

      desc "stitch BUNDLES_DIR",
           "Merge per-part SRL bundles (each bundle.json + site/) into one " \
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
        result = Suma::Srl::Stitcher.new(**stitch_options(bundles_dir)).stitch
        Utils.log "Stitched #{result.parts.size} into #{options[:out]}: " \
                  "#{result.resolved} ok, #{result.broken} broken"
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
    end
  end
end
