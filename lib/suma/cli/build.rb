# frozen_string_literal: true

require "thor"
require_relative "../thor_ext"

module Suma
  # Build command for building collections
  class Build < Thor
    # Return true to exit with non-zero status on errors
    def self.exit_on_failure?
      true
    end

    default_command :default_build

    desc "default_build METANORMA_SITE_MANIFEST",
         "Build collection specified in site manifest (`metanorma*.yml`)"
    option :compile, type: :boolean, default: true,
                     desc: "Compile or skip compile of collection"
    option :schemas_all_path, type: :string, aliases: "-s",
                              desc: "Generate file that contains all schemas in the collection."

    def default_build(metanorma_site_manifest)
      # Lazy-load dependencies only when this command is actually used
      require_relative "../processor"
      require_relative "../utils"

      unless File.exist?(metanorma_site_manifest)
        raise Errno::ENOENT, "Specified Metanorma site manifest file " \
                             "`#{metanorma_site_manifest}` not found."
      end

      # Allow errors to propagate
      run(metanorma_site_manifest, options)
    end

    private

    def run(manifest, options)
      # Set schemas_all_path to match metanorma_yaml_path
      schemas_all_path = options[:schemas_all_path] ||
        manifest.gsub("metanorma", "schemas")

      Processor.run(
        metanorma_yaml_path: manifest,
        schemas_all_path: schemas_all_path,
        compile: options[:compile],
        output_directory: "_site",
      )
    end

    def log_error(error)
      Utils.log "[ERROR] Error occurred during processing. See details below."
      Utils.log error
      Utils.log error.inspect
      Utils.log error.backtrace.join("\n")
    end
  end
end
