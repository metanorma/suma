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
                            "its own process (sequential) and reinflate. For large " \
                            "collections that OOM a single-process build (suma#94)."

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
          staged: options[:staged],
        ).run
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
