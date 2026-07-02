# frozen_string_literal: true

require_relative "express_schema"
require_relative "utils"
require "fileutils"

module Suma
  # SchemaExporter exports EXPRESS schemas from a manifest
  # with configurable options for annotations and ZIP packaging
  class SchemaExporter
    CATEGORY_MAP = {
      ExpressSchema::Type::RESOURCE => "resources",
      ExpressSchema::Type::MODULE_ARM => "modules",
      ExpressSchema::Type::MODULE_MIM => "modules",
      ExpressSchema::Type::BUSINESS_OBJECT_MODEL => "business_object_models",
      ExpressSchema::Type::CORE_MODEL => "core_model",
      ExpressSchema::Type::STANDALONE => ".",
    }.freeze

    attr_reader :schemas, :output_path, :options

    def initialize(schemas:, output_path:, options: {})
      @schemas = schemas
      @output_path = Pathname.new(output_path).expand_path
      @options = default_options.merge(options)
      @cache = build_cache
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

    # A shared, content-addressed schema cache when a cache directory is
    # configured (via the +:cache_dir+ option or the SUMA_SCHEMA_CACHE_DIR
    # environment variable), otherwise a null cache (caching disabled).
    def build_cache
      directory = options[:cache_dir] || ENV.fetch("SUMA_SCHEMA_CACHE_DIR", nil)
      return NullCache.new if directory.nil? || directory.empty?

      SchemaCache.new(directory)
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
        cache: @cache,
      )

      express_schema.save_exp(with_annotations: options[:annotations])
    end

    def determine_output_path(schema, is_standalone)
      if is_standalone
        output_path.to_s
      else
        category = categorize_schema(schema)
        output_path.join(category).to_s
      end
    end

    def categorize_schema(schema)
      type = ExpressSchema::Type.classify(id: schema.id, path: schema.path)
      CATEGORY_MAP.fetch(type, "standalone")
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
