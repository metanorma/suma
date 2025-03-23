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
    end
  end
end
