# frozen_string_literal: true

require "thor"
require_relative "../thor_ext"

module Suma
  module Cli
    # Export command for exporting EXPRESS schemas from a manifest
    class Export < Thor
      desc "export *FILES",
           "Export EXPRESS schemas from manifest files or " \
           "standalone EXPRESS files"
      option :output, type: :string, aliases: "-o", required: true,
                      desc: "Output directory path"
      option :annotations, type: :boolean, default: false,
                           desc: "Include annotations (remarks/comments)"
      option :zip, type: :boolean, default: false,
                   desc: "Create ZIP archive of exported schemas"

      def export(*files)
        require_relative "../schema_exporter"
        require_relative "../utils"
        require "expressir"

        validate_files(files)
        run(files, options)
      end

      private

      def validate_files(files)
        if files.empty?
          raise ArgumentError, "At least one file must be specified"
        end

        files.each do |file|
          unless File.exist?(file)
            raise Errno::ENOENT, "Specified file `#{file}` not found."
          end
        end
      end

      def run(files, options)
        schemas = load_schemas_from_files(files)

        exporter = SchemaExporter.new(
          schemas: schemas,
          output_path: options[:output],
          options: {
            annotations: options[:annotations],
            create_zip: options[:zip],
          },
        )

        exporter.export
      end

      def load_schemas_from_files(files)
        all_schemas = []

        files.each do |file|
          all_schemas += process_file(file)
        end

        all_schemas
      end

      def process_file(file)
        case File.extname(file).downcase
        when ".yml", ".yaml"
          load_manifest_schemas(file)
        when ".exp"
          [create_schema_from_exp_file(file)]
        else
          raise ArgumentError, "Unsupported file type: #{file}. " \
                               "Only .yml, .yaml, and .exp files are " \
                               "supported."
        end
      end

      def load_manifest_schemas(file)
        manifest = Expressir::SchemaManifest.from_file(file)
        manifest.schemas
      end

      def create_schema_from_exp_file(exp_file)
        # Create a schema object from a standalone EXPRESS file
        # The id will be determined during parsing
        StandaloneSchema.new(
          id: nil,
          path: File.expand_path(exp_file),
        )
      end

      # Simple schema class for standalone EXPRESS files
      class StandaloneSchema
        attr_accessor :id, :path

        def initialize(id:, path:)
          @id = id
          @path = path
        end
      end

      def self.exit_on_failure?
        true
      end
    end
  end
end
