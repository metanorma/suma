# frozen_string_literal: true

require_relative "express_schema"
require_relative "utils"
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
      # Check if this is a plain file (not from a manifest structure)
      is_plain_file = schema.is_a?(Cli::Export::PlainSchema)

      if is_plain_file
        # For plain files, output directly to the root
        schema_output_path = output_path.to_s
      else
        # For manifest schemas, preserve directory structure
        category = categorize_schema(schema)
        schema_output_path = output_path.join(category).to_s
      end

      express_schema = ExpressSchema.new(
        id: schema.id,
        path: schema.path.to_s,
        output_path: schema_output_path,
        is_plain_file: is_plain_file,
      )

      express_schema.save_exp(with_annotations: options[:annotations])
    end

    # rubocop:disable Metrics/MethodLength
    def categorize_schema(schema)
      path = schema.path.to_s

      # Check if this is from a manifest structure or a plain file
      case path
      when %r{/resources/}
        "resources"
      when %r{/modules/}
        "modules"
      when %r{/business_object_models/}
        "business_object_models"
      when %r{/core_model/}
        "core_model"
      else
        # Independent EXPRESS file not from a manifest structure
        "independent"
      end
    end
    # rubocop:enable Metrics/MethodLength

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
