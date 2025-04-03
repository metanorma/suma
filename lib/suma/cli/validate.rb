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

      desc "ascii EXPRESS_FILE_PATH",
           "Validate EXPRESS files for ASCII-only content"
      option :recursive, type: :boolean, default: false, aliases: "-r",
                         desc: "Validate EXPRESS files under the specified path recursively"
      option :yaml, type: :boolean, default: false, aliases: "-y",
                    desc: "Output results in YAML format"
      def ascii(express_file_path)
        require_relative "validate_ascii"

        validator = Cli::ValidateAscii.new
        validator.options = options
        validator.validate_ascii(express_file_path)
      end
    end
  end
end
