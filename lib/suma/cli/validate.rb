# frozen_string_literal: true

require "thor"

module Suma
  module Cli
    # Validate command group. Thin Thor adapter around
    # +Suma::LinkValidation+ — argument parsing, result presentation.
    # All orchestration (manifest loading, link extraction, schema
    # indexing, validation) lives in the deep module and is reachable
    # from specs without invoking Thor.
    class Validate < Thor
      desc "links SCHEMAS_FILE DOCUMENTS_PATH [OUTPUT_FILE]",
           "Extract and validate express links without creating intermediate file"
      def links(schemas_file = "schemas-srl.yml",
                documents_path = "documents",
                output_file = "validation_results.txt")
        result = LinkValidation.new(
          schemas_file: schemas_file,
          documents_path: documents_path,
          output_file: output_file,
        ).call
        puts LinkValidation.generate_summary(result)
      end
    end
  end
end
