# frozen_string_literal: true

require "fileutils"

module Suma
  # SchemaExporter exports EXPRESS schemas from a manifest
  # with configurable options for annotations and ZIP packaging
  class SchemaExporter
    attr_reader :schemas, :output_path, :options

    def initialize(schemas:, output_path:, options: {})
      @schemas = schemas
      @output_path = Pathname.new(output_path).expand_path
      @options = default_options.merge(options)
    end

    def export
      Utils.log "Exporting schemas to: #{output_path}"

      export_to_directory(schemas)
      create_zip_archive if options[:create_zip]

      Utils.log "Export complete!"
    end

    private

    def default_options
      {
        annotations: false,
        create_zip: false,
        structure: :preserve,
      }
    end

    def export_to_directory(schemas)
      schemas.each do |schema|
        export_single_schema(schema)
      end
    end

    def export_single_schema(schema)
      is_standalone = !schema.is_a?(Expressir::SchemaManifestEntry)
      schema_output_path = determine_output_path(schema, is_standalone)

      express_schema = ExpressSchema.new(
        id: schema.id,
        path: schema.path.to_s,
        output_path: schema_output_path,
        is_standalone_file: is_standalone,
      )

      express_schema.save_exp(with_annotations: options[:annotations])
    end

    def determine_output_path(schema, is_standalone)
      if is_standalone
        output_path.to_s
      else
        category = SchemaCategory.for_schema(id: schema.id, path: schema.path)
        output_path.join(category.directory).to_s
      end
    end

    # rubocop:disable Metrics/MethodLength
    def create_zip_archive
      require "zip"

      zip_path = "#{output_path}.zip"
      Utils.log "Creating ZIP archive: #{zip_path}"

      Zip::File.open(zip_path, Zip::File::CREATE) do |zipfile|
        Dir.glob("#{output_path}/**/*").each do |file|
          next if File.directory?(file)

          relative_path = file.sub("#{output_path}/", "")
          zipfile.add(relative_path, file)
        end
      end

      Utils.log "ZIP archive created: #{zip_path}"
    end
    # rubocop:enable Metrics/MethodLength
  end
end
