# frozen_string_literal: true

require "thor"
require "expressir"
require "expressir/cli"

module Suma
  module Cli
    # Top-level CLI entrypoint.
    #
    # Each command delegates to a dedicated Thor class under +Suma::Cli::+,
    # which reparses ARGV and therefore owns the canonical +option+
    # declarations. Re-declaring options here would duplicate the inner
    # classes' declarations and cause help text and validation logic to
    # drift. Options are declared in exactly one place (the inner class).
    #
    # The exception is +check_svg_quality+, which constructs its analyzer
    # inline (no inner Thor class), so its options belong here.
    class Core < Thor
      extend ThorExt::Start

      desc "build METANORMA_SITE_MANIFEST",
           "Build collection specified in site manifest (`metanorma*.yml`)"
      # Mirrors so Core accepts the switches Cli::Build reparses; the inner
      # class owns their declarations.
      option :compile, type: :boolean, default: true,
                       desc: "Compile or skip compile of collection"
      option :schemas_all_path, type: :string, aliases: "-s",
                                desc: "Generate file that contains all schemas " \
                                      "in the collection."
      option :staged, type: :boolean, default: false,
                      desc: "Memory-bounded staged build"
      option :incremental, type: :boolean, default: false,
                           desc: "Re-render only changed schemas and dependents"
      option :state_file, type: :string,
                          desc: "Path to the incremental build state file"
      option :jobs, type: :numeric, default: 1,
                    desc: "Concurrent schema export workers"
      def build(_site_manifest)
        Cli::Build.start
      end

      desc "generate-schemas METANORMA_MANIFEST_FILE SCHEMA_MANIFEST_FILE",
           "Generate EXPRESS schema manifest file from Metanorma site manifest"
      def generate_schemas(_metanorma_manifest_file, _schema_manifest_file)
        Cli::GenerateSchemas.start
      end

      desc "reformat EXPRESS_FILE_PATH",
           "Reformat EXPRESS files"
      def reformat(_express_file_path)
        Cli::Reformat.start
      end

      desc "extract-terms SCHEMA_MANIFEST_FILE GLOSSARIST_OUTPUT_PATH",
           "Extract terms from SCHEMA_MANIFEST_FILE into " \
           "Glossarist v3 format"
      option :urn, type: :string, required: true, aliases: "-u",
                   desc: "URN for the dataset source " \
                         "(used for section references)"
      option :language_code, type: :string, default: "eng", aliases: "-l",
                             desc: "Language code for the Glossarist"
      option :edition, type: :numeric,
                       desc: "Owning edition recorded on each concept"
      option :language_codes, type: :array,
                              desc: "Additional linked localization languages"
      def extract_terms(schema_manifest_file, glossarist_output_path)
        TermExtractor.new(
          schema_manifest_file,
          glossarist_output_path,
          urn: options[:urn],
          language_code: options[:language_code],
          edition: options[:edition],
          language_codes: options[:language_codes],
        ).call
      end

      desc "generate-register SCHEMA_MANIFEST_FILE OUTPUT_PATH",
           "Generate a Glossarist register.yaml with hierarchical sections"
      option :urn, type: :string, required: true, aliases: "-u",
                   desc: "URN prefix for the dataset"
      option :id, type: :string, required: true,
                  desc: "Dataset identifier (e.g. iso10303-2-express)"
      option :ref, type: :string, required: true,
                   desc: "Human-readable reference label"
      option :language_code, type: :string, default: "eng", aliases: "-l",
                             desc: "Language code for section names"
      option :owner, type: :string, default: Suma::RegisterManifestGenerator::DEFAULT_OWNER,
                     desc: "Owner of the dataset (e.g. 'ISO/TC 184/SC 4')"
      option :profile, type: :string, default: "iso10303",
                       desc: "Corpus profile (iso10303 or generic)"
      option :year, type: :numeric,
                    desc: "Edition year for the register"
      option :supersedes, type: :string,
                          desc: "URN/ref of the superseded edition"
      option :edition, type: :numeric,
                       desc: "Edition number (tagged as edition:N)"
      def generate_register(schema_manifest_file, output_path)
        RegisterManifestGenerator.new(
          schema_manifest_file,
          output_path,
          urn: options[:urn],
          id: options[:id],
          ref: options[:ref],
          language_code: options[:language_code],
          owner: options[:owner],
          profile: options[:profile],
          year: options[:year],
          supersedes: options[:supersedes],
          edition: options[:edition],
        ).generate
      end

      desc "convert-jsdai XML_FILE IMAGE_FILE OUTPUT_DIR",
           "Convert JSDAI XML and image files to SVG and EXP files"
      def convert_jsdai(_xml_file, _image_file, _output_dir)
        Cli::ConvertJsdai.start
      end

      desc "export *FILES",
           "Export EXPRESS schemas from manifest files or " \
           "standalone EXPRESS files"
      # The inner class reparses ARGV and owns the canonical declarations;
      # these mirrors exist only so Core accepts the switches it passes
      # through (Core checks unknown options before dispatch).
      option :output, type: :string, aliases: "-o", required: true,
                      desc: "Output directory path"
      option :annotations, type: :boolean, default: false,
                           desc: "Include annotations (remarks/comments)"
      option :zip, type: :boolean, default: false,
                   desc: "Create ZIP archive of exported schemas"
      option :publication, type: :string, banner: "SCHEMA_ID",
                           desc: "Export an AP publication bundle: the " \
                                 "lead schema plus its transitive " \
                                 "USE-FROM/REFERENCE closure (manifest " \
                                 "input only)"
      option :profile, type: :string, default: "iso10303",
                       desc: "Corpus profile (iso10303 or generic)"
      option :format, type: :string, default: "express", banner: "FORMAT",
                      desc: "Output format: express (default) or owl"
      option :corpus, type: :boolean, default: false,
                      desc: "OWL only: emit one ontology for the whole " \
                            "manifest instead of one per schema"
      option :urn, type: :string, banner: "URN",
                   desc: "OWL only: base URN for IRIs, before the " \
                         ":tech component " \
                         "(e.g. urn:iso:std:iso:10303:-2:ed-2:en)"
      def export(*_files)
        Cli::Export.start
      end

      desc "compare TRIAL_SCHEMA REFERENCE_SCHEMA",
           "Compare EXPRESS schemas using eengine and generate Change YAML"
      def compare(_trial_schema, _reference_schema)
        Cli::Compare.start
      end

      desc "validate SUBCOMMAND ...ARGS", "Validate express documents"
      subcommand "validate", Cli::Validate

      desc "resolve URN", "Resolve URNs to canonical JSON + HTML artifacts"
      subcommand "resolve", Cli::Resolve

      desc "check_svg_quality [PATH]",
           "Check SVG quality and sort by severity (critical files first)"
      option :pattern, type: :string, default: Cli::CheckSvgQuality::DEFAULT_PATTERN,
                       desc: "Glob pattern for finding SVG files"
      option :profile, type: :string,
                       default: Cli::CheckSvgQuality::DEFAULT_PROFILE,
                       desc: "Validation profile to use (metanorma, svg_1_2_rfc, etc.)"
      option :format, type: :string, default: "terminal",
                      desc: "Output format: terminal, yaml, json"
      option :output, type: :string, aliases: "-o",
                      desc: "Output file path"
      option :min_errors, type: :numeric,
                          desc: "Minimum error count threshold"
      option :limit, type: :numeric, default: nil,
                     desc: "Maximum number of files to show (default: unlimited)"
      option :sort, type: :string, default: "errors",
                    desc: "Sort by: errors (most errors first) or quality (lowest scores first)"
      option :progress, type: :boolean, default: false,
                        desc: "Show progress during processing"
      option :summary_only, type: :boolean, default: false,
                            desc: "Show only summary"
      def check_svg_quality(path = Cli::CheckSvgQuality::DATA_PATH)
        analyzer = Cli::CheckSvgQuality.new(
          pattern: options[:pattern],
          profile: options[:profile],
          format: options[:format],
          output: options[:output],
          min_errors: options[:min_errors],
          summary_only: options[:summary_only],
          progress: options[:progress],
          limit: options[:limit],
          sort: options[:sort],
        )
        analyzer.run(path)
      end

      desc "expressir SUBCOMMAND ...ARGS", "Expressir commands"
      subcommand "expressir", Expressir::Cli

      def self.exit_on_failure?
        true
      end
    end
  end
end
