# frozen_string_literal: true

require "thor"
require_relative "thor_ext"
require_relative "processor"
require_relative "utils"

module Suma
  class Cli < Thor
    extend ThorExt::Start

    desc "build METANORMA_SITE_MANIFEST", "Build collection specified in site manifest (`metanorma*.yml`)"
    option :compile, type: :boolean, default: true, desc: "Compile or skip compile of collection"
    option :schemas_all_path, type: :string, aliases: "-s",
                              desc: "Generate file that contains all schemas in the collection."

    def build(metanorma_site_manifest)
      unless File.exist?(metanorma_site_manifest)
        raise Errno::ENOENT, "Specified Metanorma site manifest file " \
          "`#{metanorma_site_manifest}` not found."
      end

      # Set schemas_all_path to match metanorma_yaml_path
      schemas_all_path = options[:schemas_all_path] ||
                         metanorma_site_manifest.gsub("metanorma", "schemas")

      begin
        Processor.run(
          metanorma_yaml_path: metanorma_site_manifest,
          schemas_all_path: schemas_all_path,
          compile: options[:compile],
          output_directory: "_site"
        )
      rescue StandardError => e
        Utils.log "[ERROR] Error occurred during processing. See details below."
        Utils.log e
        Utils.log e.inspect
        Utils.log e.backtrace
      end
    end
  end
end
