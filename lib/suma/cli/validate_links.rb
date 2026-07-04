# frozen_string_literal: true

require "thor"

module Suma
  module Cli
    # Deprecated: prefer +Cli::Validate#links+ (the +suma validate links+
    # subcommand). This class is retained as a backwards-compat entry
    # point — all orchestration now lives in +Suma::LinkValidation+.
    class ValidateLinks < Thor
      desc "extract_and_validate SCHEMAS_FILE DOCUMENTS_PATH [OUTPUT_FILE]",
           "Extract and validate express links without creating intermediate file"
      def extract_and_validate(schemas_file = "schemas-srl.yml",
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
