# frozen_string_literal: true

require "thor"
require_relative "thor_ext"
require_relative "cli/validate"

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
                                desc: "Generate file that contains all schemas in the collection."
      def build(_site_manifest)
        # # If no arguments, add an empty array to ensure the default command is triggered
        # args = [] if args.empty?
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
           "Glossarist v2 format"
      option :language_code, type: :string, default: "eng", aliases: "-l",
                             desc: "Language code for the Glossarist"
      def extract_terms(_schema_manifest_file, _glossarist_output_path)
        require_relative "cli/extract_terms"
        Cli::ExtractTerms.start
      end

      desc "convert-jsdai XML_FILE IMAGE_FILE OUTPUT_DIR",
           "Convert JSDAI XML and image files to SVG and EXP files"
      def convert_jsdai(_xml_file, _image_file, _output_dir)
        require_relative "cli/convert_jsdai"
        Cli::ConvertJsdai.start
      end

      desc "export *FILES",
           "Export EXPRESS schemas from manifest files or standalone EXPRESS files"
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

      desc "validate SUBCOMMAND ...ARGS", "Validate express documents"
      subcommand "validate", Cli::Validate

      def self.exit_on_failure?
        true
      end
    end
  end
end
