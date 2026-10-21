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

      desc "closure SCHEMAS_MANIFEST [DOCUMENTS_PATH]",
           "Validate referential closure: every EXPRESS-internal reference " \
           "resolves; optionally merge documentation-layer link failures"
      option :format, type: :string, default: "terminal",
                      desc: "Report format: terminal, json, yaml"
      def closure(schemas_manifest_file, documents_path = nil)
        graph = CorpusGraph.from_manifest(schemas_manifest_file)
        violations = ClosureValidator.new(graph)
          .validate_manifest(schemas_manifest_file)
        if documents_path
          violations += documentation_violations(schemas_manifest_file,
                                                 documents_path)
        end
        emit_closure_report(violations)
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

      desc "anchors SCHEMA_DOCS_PATH",
           "Validate rendered schema docs: every Expressir cross-reference " \
           "and in-page link resolves to an anchor in its HTML"
      def anchors(schema_docs_path = "schema_docs")
        violations = AnchorValidator.new(schema_docs_path).validate
        if violations.empty?
          puts "All anchors resolve: no dead links."
          return
        end

        puts violations.map { |v| "#{v.file}: #{v.link} — #{v.reason}" }
          .join("\n")
        raise Thor::Error,
              "Anchor validation failed: #{violations.size} dead link(s)"
      end

      private

      # Print the closure report and raise on any unresolved reference.
      def emit_closure_report(violations)
        if violations.empty?
          puts closure_success_message
          return
        end

        puts format_closure_report(violations)
        raise Thor::Error,
              "Referential closure failed: #{violations.size} unresolved " \
              "reference(s)"
      end

      def closure_success_message
        case options[:format]
        when "json"
          require "json"
          { "violations" => [] }.to_json
        when "yaml"
          require "yaml"
          { "violations" => [] }.to_yaml
        else
          "Referential closure OK: all references resolve."
        end
      end

      def format_closure_report(violations)
        case options[:format]
        when "json"
          require "json"
          { "violations" => violations.map(&:to_h) }.to_json
        when "yaml"
          require "yaml"
          { "violations" => violations.map(&:to_h) }.to_yaml
        else
          violations.map { |v| format_closure_line(v) }
            .sort
            .join("\n")
        end
      end

      def format_closure_line(violation)
        location = [violation.file, violation.line].compact.join(":")
        "[#{violation.kind}] #{violation.schema_id}/#{violation.owner_id} " \
          "#{violation.reference} (#{location}) — #{violation.reason}"
      end

      # Merge documentation-layer link failures into the closure report:
      # the same unresolved-reference predicate, applied by the doc-layer
      # extractor.
      def documentation_violations(schemas_file, documents_path)
        result = LinkValidation.new(
          schemas_file: schemas_file,
          documents_path: documents_path,
          output_file: nil,
        ).call
        result.unresolved.map { |issue| documentation_violation(issue) }
      rescue StandardError => e
        Utils.log "documentation-layer validation skipped: #{e.message}"
        []
      end

      def documentation_violation(issue)
        ClosureValidator::UnresolvedReference.new(
          file: issue.file.to_s,
          line: issue.line,
          schema_id: issue.link.to_s.split(".").first,
          owner_id: "(documentation)",
          kind: "documentation",
          reference: issue.link,
          reason: issue.reason,
        )
      end

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
