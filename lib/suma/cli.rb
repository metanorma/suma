# frozen_string_literal: true

require "thor"
require_relative "thor_ext"

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

      desc "links SUBCOMMAND ...ARGS", "Manage EXPRESS links"
      def links(*_args)
        require_relative "cli/links"
        Cli::Links.start
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

      desc "validate-ascii EXPRESS_FILE_PATH",
           "Validate EXPRESS files for ASCII-only content"
      option :recursive, type: :boolean, default: false, aliases: "-r",
                         desc: "Validate EXPRESS files under the specified " \
                               "path recursively"
      option :yaml, type: :boolean, default: false, aliases: "-y",
                    desc: "Output results in YAML format"
      def validate_ascii(_express_file_path)
        require_relative "cli/validate_ascii"
        Cli::ValidateAscii.start
      end
    end
  end
end
