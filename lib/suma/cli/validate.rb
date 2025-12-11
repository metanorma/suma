# frozen_string_literal: true

require "thor"

module Suma
  module Cli
    # Main validate command that groups the validation subcommands
    class Validate < Thor
      desc "links SCHEMAS_FILE DOCUMENTS_PATH [OUTPUT_FILE]",
           "Extract and validate express links without creating intermediate file"
      def links(*args)
        require_relative "validate_links"

        # Forward the command to ValidateLinks
        links = Cli::ValidateLinks.new
        links.extract_and_validate(*args)
      end
    end
  end
end
