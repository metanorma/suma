# frozen_string_literal: true

require "thor"
require_relative "thor_ext"
require_relative "cli/validate"

module Suma
  module Cli
    # Core command class for handling CLI entrypoints
    class Core < Thor
      extend ThorExt::Start

      desc "build METANORMA_SITE_MANIFEST",
           "Build collection specified in site manifest (`metanorma*.yml`)"
      option :compile, type: :boolean, default: true,
                       desc: "Compile or skip compile of collection"
      option :schemas_all_path, type: :string, aliases: "-s",
                                desc: "Generate file that contains all schemas in the collection."
      def build(_site_manifest)
        # # If no arguments, add an empty array to ensure the default command is triggered
        # args = [] if args.empty?
        require_relative "cli/build"
        Cli::Build.start
      end

      desc "generate_schemas METANORMA_MANIFEST_FILE SCHEMA_MANIFEST_FILE",
           "Generate EXPRESS schema manifest file from Metanorma site manifest"
      option :exclude_paths, type: :string, default: nil, aliases: "-e",
                             desc: "Exclude schemas paths by pattern " \
                                   "(e.g. `*_lf.exp`)"
      def generate_schemas(_metanorma_manifest_file, _schema_manifest_file)
        require_relative "cli/generate_schemas"
        Cli::GenerateSchemas.start
      end

      desc "reformat EXPRESS_FILE_PATH",
           "Reformat EXPRESS files"
      option :recursive, type: :boolean, default: false, aliases: "-r",
                         desc: "Reformat EXPRESS files under the specified " \
                               "path recursively"
      def reformat(_express_file_path)
        require_relative "cli/reformat"
        Cli::Reformat.start
      end

      desc "validate SUBCOMMAND ...ARGS", "Validate express documents"
      subcommand "validate", Cli::Validate

      def self.exit_on_failure?
        true
      end
    end
  end
end
