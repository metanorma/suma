# frozen_string_literal: true

require "thor"

module Suma
  module Cli
    # Build command for building collections
    class Build < Thor
      desc "build METANORMA_SITE_MANIFEST",
           "Build collection specified in site manifest (`metanorma*.yml`)"
      option :compile, type: :boolean, default: true,
                       desc: "Compile or skip compile of collection"
      option :schemas_all_path, type: :string, aliases: "-s",
                                desc: "Generate file that contains all schemas in the collection."
      option :staged, type: :boolean, default: false,
                      desc: "Memory-bounded staged build: compile each member in " \
                            "its own process (sequential unless --staged-workers " \
                            "is given) and reinflate. For large collections that " \
                            "OOM a single-process build (suma#94)."
      option :staged_workers, type: :numeric, default: 1,
                              desc: "Concurrent staged render processes (batched " \
                                    "members per process; requires --staged)"
      option :staged_batch_size, type: :numeric,
                                 desc: "Members per staged render process " \
                                       "(default: 25)"
      option :incremental, type: :boolean, default: false,
                           desc: "Re-render only changed schemas and their " \
                                 "transitive dependents (state file defaults " \
                                 "to plain_schemas/.suma-build-state.json)"
      option :state_file, type: :string,
                          desc: "Path to the incremental build state file"
      option :jobs, type: :numeric, default: 1,
                    desc: "Concurrent schema export workers (document " \
                          "compilation remains sequential)"
      option :provenance, type: :string,
                          desc: "Write a provenance manifest (sha256 of inputs " \
                                "and outputs + toolchain versions) to this path"
      option :sign, type: :string, banner: "METHOD",
                    desc: "Sign the provenance manifest: minisign or sigstore"
      option :sign_key, type: :string,
                        desc: "Signing key (minisign requires it; sigstore " \
                              "signs keylessly when omitted)"
      option :no_valid, type: :boolean, default: false,
                        desc: "Skip Metanorma document validation " \
                              "(equivalent of metanorma --no-valid)"

      def build(metanorma_site_manifest)
        unless File.exist?(metanorma_site_manifest)
          raise Errno::ENOENT, "Specified Metanorma site manifest file " \
                               "`#{metanorma_site_manifest}` not found."
        end

        # Allow errors to propagate
        run(metanorma_site_manifest, options)
      end

      private

      def run(manifest, options)
        schemas_all_path = options[:schemas_all_path] ||
          manifest.gsub("metanorma", "schemas")

        Processor.new(
          metanorma_yaml_path: manifest,
          schemas_all_path: schemas_all_path,
          compile: options[:compile],
          output_directory: "_site",
          incremental: options[:incremental],
          state_file: options[:state_file],
          jobs: options[:jobs],
          provenance_file: options[:provenance],
          sign_method: options[:sign],
          sign_key: options[:sign_key],
          no_valid: options[:no_valid],
          **staged_options(options),
        ).run
      end

      def staged_options(options)
        { staged: options[:staged],
          staged_workers: options[:staged_workers],
          staged_batch_size: options[:staged_batch_size] }
      end

      def log_error(error)
        Utils.log "[ERROR] Error occurred during processing. See details below."
        Utils.log error
        Utils.log error.inspect
        Utils.log error.backtrace.join("\n")
      end
    end
  end
end
