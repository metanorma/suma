# frozen_string_literal: true

require "thor"
require "pathname"

module Suma
  module Cli
    # Export command. Thin Thor adapter that constructs
    # +Suma::ExpressSchema+ instances from manifest entries or
    # standalone +.exp+ files, then delegates the actual writing to
    # +Suma::SchemaExporter+.
    #
    # The schema-type → output-subdirectory mapping lives in
    # +Suma::SchemaCategory+, the single source of truth. The exporter
    # itself never classifies — it consumes loaded ExpressSchema
    # objects whose output paths were set by this adapter.
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
        schemas = files.flat_map { |file| build_schemas(file) }

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

      def build_schemas(file)
        case File.extname(file).downcase
        when ".yml", ".yaml"
          build_from_manifest(file)
        when ".exp"
          [build_standalone(file)]
        else
          raise ArgumentError, "Unsupported file type: #{file}. " \
                               "Only .yml, .yaml, and .exp files are " \
                               "supported."
        end
      end

      def build_from_manifest(file)
        manifest = Expressir::SchemaManifest.from_file(file)
        manifest.schemas.map { |entry| build_from_manifest_entry(entry) }
      end

      def build_from_manifest_entry(entry)
        category = SchemaCategory.for_schema(id: entry.id, path: entry.path)
        ExpressSchema.new(
          id: entry.id,
          path: entry.path.to_s,
          output_path: output_root.join(category.directory).to_s,
          is_standalone_file: false,
        )
      end

      def build_standalone(exp_file)
        ExpressSchema.new(
          id: nil,
          path: File.expand_path(exp_file),
          output_path: output_root.to_s,
          is_standalone_file: true,
        )
      end

      def output_root
        Pathname.new(options[:output]).expand_path
      end

      def self.exit_on_failure?
        true
      end
    end
  end
end
