# frozen_string_literal: true

require "thor"
require_relative "thor_ext"
require_relative "cli/validate"
require_relative "cli/check_svg_quality"
require "expressir"
require "expressir/cli"

module Suma
  module Cli
    # Core command class for handling CLI entrypoints
    class Core < Thor
      extend ThorExt::Start

      desc "build METANORMA_SITE_MANIFEST",
           "Build collection specified in site manifest (`metanorma*.yml`)"
      option :compile, type: :boolean, default: true,
                       desc: "Compile or skip compile of collection"
      option :schemas_all_path, type: :string, aliases: "-s",
                                desc: "Generate file that contains all " \
                                      "schemas in the collection."
      def build(_site_manifest)
        require_relative "cli/build"
        Cli::Build.start
      end

      desc "generate-schemas METANORMA_MANIFEST_FILE SCHEMA_MANIFEST_FILE",
           "Generate EXPRESS schema manifest file from Metanorma site manifest"
      option :exclude_paths, type: :string, default: nil, aliases: "-e",
                             desc: "Exclude schemas paths by pattern " \
                                   "(e.g. `*_lf.exp`)"
      def generate_schemas(_metanorma_manifest_file, _schema_manifest_file)
        require_relative "cli/generate_schemas"
        Cli::GenerateSchemas.start
      end

      desc "reformat EXPRESS_FILE_PATH",
           "Reformat EXPRESS files"
      option :recursive, type: :boolean, default: false, aliases: "-r",
                         desc: "Reformat EXPRESS files under the specified " \
                               "path recursively"
      def reformat(_express_file_path)
        require_relative "cli/reformat"
        Cli::Reformat.start
      end

      desc "extract-terms SCHEMA_MANIFEST_FILE GLOSSARIST_OUTPUT_PATH",
           "Extract terms from SCHEMA_MANIFEST_FILE into " \
           "Glossarist v3 format"
      option :language_code, type: :string, default: "eng", aliases: "-l",
                             desc: "Language code for the Glossarist"
      option :urn, type: :string, aliases: "-u",
                   desc: "URN for the dataset source " \
                         "(used for section references)"
      def extract_terms(_schema_manifest_file, _glossarist_output_path)
        require_relative "cli/extract_terms"
        Cli::ExtractTerms.start
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
      def generate_register(_schema_manifest_file, _output_path)
        require_relative "cli/generate_register"
        Cli::GenerateRegister.start
      end

      desc "convert-jsdai XML_FILE IMAGE_FILE OUTPUT_DIR",
           "Convert JSDAI XML and image files to SVG and EXP files"
      def convert_jsdai(_xml_file, _image_file, _output_dir)
        require_relative "cli/convert_jsdai"
        Cli::ConvertJsdai.start
      end

      desc "export *FILES",
           "Export EXPRESS schemas from manifest files or " \
           "standalone EXPRESS files"
      option :output, type: :string, aliases: "-o", required: true,
                      desc: "Output directory path"
      option :annotations, type: :boolean, default: false,
                           desc: "Include annotations (remarks/comments)"
      option :zip, type: :boolean, default: false,
                   desc: "Create ZIP archive of exported schemas"
      def export(*_files)
        require_relative "cli/export"
        Cli::Export.start
      end

      desc "compare TRIAL_SCHEMA REFERENCE_SCHEMA",
           "Compare EXPRESS schemas using eengine and generate Change YAML"
      option :output, type: :string, aliases: "-o",
                      desc: "Output Change YAML file path"
      option :version, type: :string, aliases: "-v", required: true,
                       desc: "Version number for this change version"
      option :mode, type: :string, default: "resource",
                    desc: "Schema comparison mode (resource/module)"
      option :trial_stepmod, type: :string,
                             desc: "Override auto-detected trial repo root"
      option :reference_stepmod, type: :string,
                                 desc: "Override auto-detected reference repo root"
      option :verbose, type: :boolean, default: false,
                       desc: "Enable verbose output"
      def compare(_trial_schema, _reference_schema)
        require_relative "cli/compare"
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
        require_relative "cli/check_svg_quality"

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
