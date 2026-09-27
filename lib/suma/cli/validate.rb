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
      def self.exit_on_failure?
        true
      end
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

      desc "mappings DOCUMENTS_PATH",
           "Validate module mapping.yaml links and reference paths " \
           "against the parsed module corpus; only NEW drift " \
           "(not in the baseline) fails"
      option :baseline, type: :string, default: nil,
                        desc: "Baseline YAML path (default: " \
                              "mapping-drift-baseline.yml under DOCUMENTS_PATH)"
      option :write_baseline, type: :boolean, default: false,
                              desc: "Write the scanned drift as the new " \
                                    "baseline instead of checking"
      def mappings(documents_path = "documents")
        drift = MappingDrift.new(documents_path)
        path = options[:baseline] || default_baseline_path(documents_path)

        return write_baseline(drift, path) if options[:write_baseline]

        assert_baseline!(path)
        fail_on_new_drift(*drift.check(path), path)
      end

      private

      def default_baseline_path(documents_path)
        File.join(documents_path, "mapping-drift-baseline.yml")
      end

      def assert_baseline!(path)
        return if File.file?(path)

        raise Thor::Error, "no baseline at #{path} — generate one with " \
                           "--write-baseline and commit it"
      end

      def fail_on_new_drift(report, fresh, path)
        say "#{report.entries.size} drift entr(ies), #{fresh.size} new vs #{path}"
        return if fresh.empty?

        raise Thor::Error, "#{fresh.size} new mapping drift:\n#{fresh.join("\n")}"
      end

      def write_baseline(drift, path)
        report = drift.scan
        File.write(path, report.to_yaml)
        say "baseline written: #{path} (#{report.entries.size} entries)"
      end
    end
  end
end
