# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require_relative "eengine/wrapper"
require_relative "eengine_converter"

module Suma
  class SchemaComparer
    attr_reader :trial_schema, :reference_schema, :options

    def initialize(trial_schema, reference_schema, options = {})
      @trial_schema = trial_schema
      @reference_schema = reference_schema
      @options = options
    end

    def compare
      validate_inputs

      trial_stepmod = options[:trial_stepmod] || detect_repo_root(trial_schema)
      reference_stepmod = options[:reference_stepmod] || detect_repo_root(reference_schema)

      out_dir = Dir.mktmpdir("eengine-compare-")

      result = Eengine::Wrapper.compare(
        trial_schema,
        reference_schema,
        mode: options[:mode] || "resource",
        trial_stepmod: trial_stepmod,
        reference_stepmod: reference_stepmod,
        out_dir: out_dir,
      )

      unless result[:has_changes]
        FileUtils.rm_rf(out_dir) if File.directory?(out_dir)
        return nil
      end

      raise Suma::CompilationError, "XML output not found" unless result[:xml_path]

      convert_to_change_yaml(result[:xml_path], out_dir)
    ensure
      FileUtils.rm_rf(out_dir) if out_dir && File.directory?(out_dir)
    end

    private

    def validate_inputs
      unless File.exist?(trial_schema)
        raise Suma::SchemaNotFoundError,
              "Trial schema not found: #{trial_schema}"
      end

      unless File.exist?(reference_schema)
        raise Suma::SchemaNotFoundError,
              "Reference schema not found: #{reference_schema}"
      end

      unless Eengine::Wrapper.available?
        raise Suma::EengineNotAvailableError,
              "eengine not found in PATH. Install from:\n  " \
              "macOS: https://github.com/expresslang/homebrew-eengine\n  " \
              "Linux: https://github.com/expresslang/eengine-releases"
      end
    end

    def detect_repo_root(schema_path)
      current = File.expand_path(File.dirname(schema_path))

      loop do
        return current if File.directory?(File.join(current, ".git"))

        parent = File.dirname(current)
        break if parent == current

        current = parent
      end

      File.dirname(schema_path)
    end

    def convert_to_change_yaml(xml_path, _out_dir)
      schema_name = extract_schema_name(trial_schema)
      output_path = determine_output_path

      existing_schema = nil
      if File.exist?(output_path)
        require "expressir/changes"
        existing_schema = Expressir::Changes::SchemaChange.from_file(output_path)
      end

      converter = EengineConverter.new(xml_path, schema_name)
      change_schema = converter.convert(
        version: options[:version],
        existing_change_schema: existing_schema,
      )

      change_schema.to_file(output_path)
      output_path
    end

    def extract_schema_name(path)
      basename = File.basename(path, ".exp")
      basename.sub(/_\d+$/, "")
    end

    def determine_output_path
      options[:output] || begin
        base = extract_schema_name(trial_schema)
        dir = File.dirname(trial_schema)
        File.join(dir, "#{base}.changes.yaml")
      end
    end
  end
end
