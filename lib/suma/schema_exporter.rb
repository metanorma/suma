# frozen_string_literal: true

require "fileutils"

module Suma
  # Exports EXPRESS schemas to a directory, with optional ZIP packaging.
  #
  # Pure sink: the exporter accepts already-loaded +Suma::ExpressSchema+
  # instances and writes their content to disk. Construction of those
  # instances (with the right +output_path+ and +is_standalone_file+
  # flags) is the caller's responsibility — the exporter does not
  # reach across the seam to inspect manifest entries or classify
  # schema types itself.
  #
  # This is a deep module: a small interface (one +export+ method, one
  # option hash) backed by save_exp + zip packaging. The CLI and
  # SchemaCollection adapters construct ExpressSchema instances; the
  # exporter never inspects their shape.
  class SchemaExporter
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

    def export_to_directory(schemas)
      schemas.each { |schema| export_single_schema(schema) }
    end

    # Reuse cached plain/annotated output when the schema source is unchanged,
    # otherwise generate it via +save_exp+ and cache the result. The Expressir
    # parse (the cost) happens only on a cache miss. Caching is an orchestration
    # concern, so it lives here in the service rather than in the ExpressSchema
    # data model.
    def export_single_schema(schema)
      source = File.read(schema.path.to_s, encoding: "UTF-8")
      cached = @cache.fetch(source, annotations: options[:annotations])
      cached ? write_cached(schema, cached) : generate_and_cache(schema, source)
    end

    def generate_and_cache(schema, source)
      schema.save_exp(with_annotations: options[:annotations])
      content = File.read(schema.filename_plain)
      @cache.store(source, annotations: options[:annotations], content: content)
    end

    def write_cached(schema, content)
      relative = Pathname.new(schema.filename_plain).relative_path_from(Dir.pwd)
      Utils.log "Save schema (cached): #{relative}"
      FileUtils.mkdir_p(File.dirname(schema.filename_plain))
      File.write(schema.filename_plain, content)
    end

    # A shared, content-addressed cache when a cache directory is configured
    # (via the +:cache_dir+ option or the SUMA_SCHEMA_CACHE_DIR environment
    # variable), otherwise a null cache (caching disabled).
    def build_cache
      directory = options[:cache_dir] || ENV.fetch("SUMA_SCHEMA_CACHE_DIR", nil)
      return NullCache.new if directory.nil? || directory.empty?

      SchemaCache.new(directory)
    end

    # rubocop:disable Metrics/MethodLength
    def create_zip_archive
      require "zip"

      zip_path = "#{output_path}.zip"
      Utils.log "Creating ZIP archive: #{zip_path}"

      Zip::File.open(zip_path, create: true) do |zipfile|
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
