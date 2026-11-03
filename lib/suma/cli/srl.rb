# frozen_string_literal: true

require "thor"

module Suma
  module Cli
    # SRL delivery commands (TCSC410303-2952): merge independently
    # rendered per-part bundles into one stitched site with resolved
    # cross-document references.
    class Srl < Thor
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
        result = Srl::Stitcher.new(**stitch_options(bundles_dir)).stitch
        Utils.log "Stitched #{result.parts.size} into #{options[:out]}: " \
                  "#{result.resolved} ok, #{result.broken} broken"
      end

      private

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
