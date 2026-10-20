# frozen_string_literal: true

require "yaml"

require "thor"

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
      option :typed_output, type: :string, banner: "FILE",
                            desc: "Write the typed ChangeManifest " \
                                  "(classification + descriptions) as YAML"
      option :changelog, type: :boolean, default: false,
                         desc: "Print a markdown changelog for the changes"
      option :impact, type: :boolean, default: false,
                      desc: "Print affected schemas and AP publications " \
                            "(requires --manifest)"
      option :manifest, type: :string, banner: "SCHEMAS_YAML",
                        desc: "Corpus schema manifest, for --impact"

      def compare(trial_schema, reference_schema)
        comparer = SchemaComparer.new(trial_schema, reference_schema, options)

        result = comparer.compare

        if result.nil?
          say "No changes detected between schemas", :yellow
          return
        end

        say "Change YAML file: #{result}", :green
        report_typed_changes(result, trial_schema)
      rescue Suma::Error => e
        raise Thor::Error, e.message
      end

      private

      def report_typed_changes(change_yaml, trial_schema)
        manifest = ChangeManifest.from_file(change_yaml,
                                            version: options[:version])
        write_typed_output(manifest)
        say manifest.to_changelog if options[:changelog]
        print_impact(manifest, trial_schema) if options[:impact]
      end

      def write_typed_output(manifest)
        path = options[:typed_output]
        return unless path

        File.write(path, manifest.to_yaml)
        say "Typed change manifest: #{path}", :green
      end

      def print_impact(manifest, trial_schema)
        unless options[:manifest]
          raise Thor::Error, "--impact requires --manifest SCHEMAS_YAML"
        end

        graph = CorpusGraph.from_manifest(options[:manifest])
        impact = ChangeImpact.new(graph, options[:manifest])
          .report(changed_schema_id(manifest, trial_schema))
        say impact.to_yaml
      end

      def changed_schema_id(manifest, trial_schema)
        manifest.schema || File.basename(trial_schema, ".exp")
      end
    end
  end
end
