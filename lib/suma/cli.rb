# frozen_string_literal: true

require "thor"
require_relative "thor_ext"

module Suma
  class Cli < Thor
    extend ThorExt::Start

    desc "build METANORMA_SITE_MANIFEST",
         "Build collection specified in site manifest (`metanorma*.yml`)"
    def build(*args)
      # If no arguments, add an empty array to ensure the default command is triggered
      args = [] if args.empty?
      require_relative "cli/build"
      Build.start(args)
    end

    desc "links SUBCOMMAND ...ARGS", "Manage EXPRESS links"
    def links(*args)
      require_relative "cli/links"
      Links.start(args)
    end
  end
end
