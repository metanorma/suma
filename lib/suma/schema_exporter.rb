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
        schema.save_exp(with_annotations: options[:annotations])
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
