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
           "hrefs to files, fragments to anchors in their target. Without " \
           "--expectations the gate is zero broken links; with one, the " \
           "manifest's thresholds (broken_links_max included) govern. " \
           "Intra-file fragment hrefs are reported but do not fail."
      option :out, type: :string,
                   desc: "Also write the report as JSON to this path"
      option :no_fragments, type: :boolean, default: false,
                            desc: "Skip fragment checking (file existence only)"
      option :expectations, type: :string,
                            desc: "YAML manifest of site-shape thresholds " \
                                  "(sections_min, index_pages, " \
                                  "schema_attachments_min, schema_docs_min, " \
                                  "missing_express_max, broken_links_max); " \
                                  "violations fail the verify"

      def verify(site_dir)
        result = Suma::Delivery::SiteVerifier.new(site_dir,
                                                  **verify_options).verify
        log_verify(result)
        failures = expectation_failures(result)
        verify_failures(result, failures)
      end

      # Without an expectations manifest the contract is zero broken
      # links. With one, broken_links_max IS the broken-link contract:
      # the unconditional raise would fire first and make the cap
      # unreachable (TRThurman, iso-10303#835). Defined inside
      # no_commands so Thor does not register a command for a helper
      # and warn about the missing usage/description on every run.
      no_commands do
        def verify_failures(result, failures)
          if options[:expectations]
            raise "expectations violated: #{failures.join('; ')}" unless
              failures.empty?
          elsif result.broken_count.zero?
            nil
          else
            raise "broken links found (#{result.broken_count})"
          end
        end
      end

      desc "resolve-fragments SITE_DIR",
           "Assembly-time cross-page fragment resolution: repoint " \
           "same-page fragment hrefs whose target renders on exactly " \
           "one other page of the stitched site. Ambiguous matches are " \
           "left untouched."
      def resolve_fragments(site_dir)
        result = Suma::Delivery::CrossPageFragments.new(site_dir).repair
        Utils.log "Fragments: #{result[:own]} own-page fine, " \
                  "#{result[:remapped]} remapped cross-page, " \
                  "#{result[:ambiguous]} ambiguous left, " \
                  "#{result[:unresolved]} unresolved"
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

      desc "pack PART", "Capture a part's built _site/ into a " \
                        "stitcher-ready bundle: normalize the per-doc " \
                        "layout, scan anchors and unresolved-eref spans, " \
                        "copy the owned schema attachments, and write " \
                        "<srl-build-base>/parts/<part>/bundle.json"
      option :srl_build_base, type: :string,
                              desc: "SRL build base holding plan.json and " \
                                    "wt/<part>/_site (default: " \
                                    "$SRL_BUILD_BASE or ~/work/srl-build)"
      option :repo_root, type: :string, default: ".",
                         desc: "Repository root holding the part's " \
                               "collection.yml"
      option :skip_layout, type: :boolean, default: false,
                           desc: "Skip layout normalization (assume " \
                                 "already done)"

      def pack(part)
        result = Suma::Delivery::Pack.new(**pack_options(part)).pack
        Utils.log "Packed #{part}: #{result.iso_name} into #{result.bundle_dir}"
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

      def load_expectations
        return unless options[:expectations]

        Suma::Delivery::Expectations
          .from_yaml(File.read(options[:expectations]))
      end

      def expectation_failures(result)
        expectations = load_expectations or return []
        expectations.violations(result.report,
                                result.report["broken_links"])
      end

      def log_verify(result)
        write_report(result.report) if options[:out]
        Utils.log verify_summary(result)
      end

      def verify_summary(result)
        r = result.report
        "Links: #{r['total_links']} total, #{r['broken_links'].size} " \
          "broken; fragments: #{r['total_fragments']} total, " \
          "#{r['broken_fragments'].size} broken; " \
          "#{r['cross_document_links']} cross-document; " \
          "#{inventory_summary(r)}"
      end

      def inventory_summary(report)
        inv = report["inventory"]
        "site: sections=#{inv['sections']} " \
          "indexes=#{inv['index_pages']} " \
          "attachments=#{inv['schema_attachments']} " \
          "schema_docs=#{inv['schema_docs']}; " \
          "missing-express pages=#{report['missing_express_pages'].size}"
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

      def pack_options(part)
        {
          part: part,
          srl_build_base: options[:srl_build_base] || ENV["SRL_BUILD_BASE"] ||
            File.expand_path("~/work/srl-build"),
          repo_root: options[:repo_root],
          skip_layout: options[:skip_layout],
        }
      end
    end
  end
end
