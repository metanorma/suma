# frozen_string_literal: true

require_relative "express_schema"
require_relative "utils"
require "fileutils"

module Suma
  # SchemaExporter exports EXPRESS schemas from a manifest
  # with configurable options for annotations and ZIP packaging
  class SchemaExporter
    attr_reader :config, :output_path, :options

    def initialize(config:, output_path:, options: {})
      @config = config
      @output_path = Pathname.new(output_path).expand_path
      @options = default_options.merge(options)
    end

    def export
      Utils.log "Exporting schemas to: #{output_path}"

      schemas = config.schemas
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
      category = categorize_schema(schema)
      schema_output_path = output_path.join(category).to_s

      express_schema = ExpressSchema.new(
        id: schema.id,
        path: schema.path.to_s,
        output_path: schema_output_path
      )

      express_schema.save_exp(with_annotations: options[:annotations])
    end

    def categorize_schema(schema)
      path = schema.path.to_s

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
        "other"
      end
    end

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
  end
end
