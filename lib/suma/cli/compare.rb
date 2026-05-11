# frozen_string_literal: true

require "thor"
require_relative "../schema_comparer"

module Suma
  module Cli
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
                       desc: "Version number for this change version"
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
        comparer = SchemaComparer.new(trial_schema, reference_schema, options)

        result = comparer.compare

        if result.nil?
          say "No changes detected between schemas", :yellow
        else
          say "Change YAML file: #{result}", :green
        end
      rescue Suma::Error => e
        raise Thor::Error, e.message
      end
    end
  end
end
