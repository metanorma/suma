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
      def extract_terms(schema_manifest_file, glossarist_output_path)
        TermExtractor.new(
          schema_manifest_file,
          glossarist_output_path,
          urn: options[:urn],
          language_code: options[:language_code],
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
      def generate_register(schema_manifest_file, output_path)
        RegisterManifestGenerator.new(
          schema_manifest_file,
          output_path,
          urn: options[:urn],
          id: options[:id],
          ref: options[:ref],
          language_code: options[:language_code],
          owner: options[:owner],
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
