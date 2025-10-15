# frozen_string_literal: true

require "thor"
require_relative "../eengine/wrapper"
require_relative "../eengine_converter"

module Suma
  module Cli
    # Command to compare EXPRESS schemas using eengine
    class Compare < Thor
      desc "compare TRIAL_SCHEMA REFERENCE_SCHEMA",
           "Compare EXPRESS schemas using eengine and generate Change YAML"
      long_desc <<~DESC
        Compare two EXPRESS schemas from different git branches/checkouts.

        Typical workflow:
          1. Check out old version of repo at /path/to/repo-old
          2. Check out new version of repo at /path/to/repo-new
          3. Run comparison:
             suma compare \\
               /path/to/repo-new/schemas/.../schema.exp \\
               /path/to/repo-old/schemas/.../schema.exp \\
               --version 2

        The command will:
          - Auto-detect repository roots from schema paths
          - Use those as stepmod paths for eengine
          - Generate/update the .changes.yaml file in the new repo
      DESC

      option :output, type: :string, aliases: "-o",
                      desc: "Output Change YAML file path " \
                            "(default: {schema}.changes.yaml in trial schema directory)"
      option :version, type: :string, aliases: "-v", required: true,
                       desc: "Version number for this change edition"
      option :mode, type: :string, default: "resource",
                    enum: ["resource", "module"],
                    desc: "Schema comparison mode"
      option :trial_stepmod, type: :string,
                             desc: "Override auto-detected trial repo root"
      option :reference_stepmod, type: :string,
                                 desc: "Override auto-detected reference repo root"
      option :verbose, type: :boolean, default: false,
                       desc: "Enable verbose output"

      def compare(trial_schema, reference_schema)
        # Validate schema files exist
        unless File.exist?(trial_schema)
          say "Error: Trial schema not found: #{trial_schema}", :red
          exit 1
        end

        unless File.exist?(reference_schema)
          say "Error: Reference schema not found: #{reference_schema}", :red
          exit 1
        end

        # Check eengine availability
        unless Eengine::Wrapper.available?
          say "Error: eengine not found in PATH", :red
          say "Install eengine following instructions at:"
          say "  macOS: https://github.com/expresslang/homebrew-eengine"
          say "  Linux: https://github.com/expresslang/eengine-releases"
          exit 1
        end

        # Auto-detect repo roots
        trial_stepmod = options[:trial_stepmod] ||
          detect_repo_root(trial_schema)
        reference_stepmod = options[:reference_stepmod] ||
          detect_repo_root(reference_schema)

        if options[:verbose]
          say "Using eengine version: #{Eengine::Wrapper.version}", :green
          say "Trial repo root: #{trial_stepmod}", :cyan
          say "Reference repo root: #{reference_stepmod}", :cyan
        end

        # Create a temporary directory for eengine output
        require "tmpdir"
        out_dir = nil
        out_dir = Dir.mktmpdir("eengine-compare-")

        # Run comparison
        result = Eengine::Wrapper.compare(
          trial_schema,
          reference_schema,
          mode: options[:mode],
          trial_stepmod: trial_stepmod,
          reference_stepmod: reference_stepmod,
          out_dir: out_dir,
        )

        unless result[:has_changes]
          say "No changes detected between schemas", :yellow
          # Clean up temp directory
          FileUtils.rm_rf(out_dir) if out_dir && File.directory?(out_dir)
          return
        end

        unless result[:xml_path]
          say "Error: XML output not found", :red
          exit 1
        end

        if options[:verbose]
          say "Comparison XML generated: #{result[:xml_path]}", :green
        end

        # Convert to Change YAML
        convert_to_change_yaml(result[:xml_path], trial_schema, out_dir)
      rescue Eengine::EengineError => e
        # Clean up temp directory
        FileUtils.rm_rf(out_dir) if out_dir && File.directory?(out_dir)
        say "Error: #{e.message}", :red
        say e.stderr if e.respond_to?(:stderr) && options[:verbose]
        exit 1
      end

      private

      def detect_repo_root(schema_path)
        # Walk up from schema path to find .git directory
        current = File.expand_path(File.dirname(schema_path))

        loop do
          if File.directory?(File.join(current, ".git"))
            return current
          end

          parent = File.dirname(current)
          break if parent == current # reached root

          current = parent
        end

        # If no .git found, use the directory containing the schema
        # (for non-git workflows)
        File.dirname(schema_path)
      end

      def convert_to_change_yaml(xml_path, trial_schema, out_dir)
        schema_name = extract_schema_name(trial_schema)
        output_path = determine_output_path(trial_schema)

        # Load existing ChangeSchema if it exists
        existing_schema = if File.exist?(output_path)
                            if options[:verbose]
                              say "Loading existing change schema: " \
                                  "#{output_path}", :cyan
                            end
                            require "expressir/changes"
                            Expressir::Changes::SchemaChange.from_file(output_path)
                          end

        # Convert using Suma's converter
        converter = EengineConverter.new(xml_path, schema_name)
        change_schema = converter.convert(
          version: options[:version],
          existing_change_schema: existing_schema,
        )

        # Save using Expressir model
        change_schema.to_file(output_path)

        # Determine what action was taken
        if existing_schema
          existing_edition = existing_schema.editions.find do |ed|
            ed.version == options[:version]
          end

          say "Change YAML file updated: #{output_path}", :green
          if existing_edition
            say "  Replaced existing version #{options[:version]}", :green
          else
            say "  Added version #{options[:version]} to change editions",
                :green
          end
        else
          say "Change YAML file created: #{output_path}", :green
        end

        if options[:verbose]
          say "\nGenerated change schema content:", :cyan
          say File.read(output_path)
        end

        # Clean up temp directory and XML file
        FileUtils.rm_rf(out_dir) if out_dir && File.directory?(out_dir)
      end

      def extract_schema_name(path)
        # Remove version suffix if present (e.g., schema_1.exp -> schema)
        basename = File.basename(path, ".exp")
        basename.sub(/_\d+$/, "")
      end

      def determine_output_path(trial_schema)
        if options[:output]
          options[:output]
        else
          # Place .changes.yaml next to the trial schema in the NEW repo
          base = extract_schema_name(trial_schema)
          dir = File.dirname(trial_schema)
          File.join(dir, "#{base}.changes.yaml")
        end
      end
    end
  end
end
