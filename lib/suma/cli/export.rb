# frozen_string_literal: true

require "thor"
require_relative "../thor_ext"

module Suma
  module Cli
    # Export command for exporting EXPRESS schemas from a manifest
    class Export < Thor
      desc "export MANIFEST_FILE",
           "Export EXPRESS schemas from manifest"
      option :output, type: :string, aliases: "-o", required: true,
                      desc: "Output directory path"
      option :additional, type: :array, aliases: "-a",
                          desc: "Additional schemas manifest files to merge (can be specified multiple times)"
      option :annotations, type: :boolean, default: false,
                           desc: "Include annotations (remarks/comments)"
      option :zip, type: :boolean, default: false,
                   desc: "Create ZIP archive of exported schemas"

      def export(manifest_file)
        require_relative "../schema_exporter"
        require_relative "../utils"
        require "expressir"

        unless File.exist?(manifest_file)
          raise Errno::ENOENT, "Specified manifest file " \
                               "`#{manifest_file}` not found."
        end

        run(manifest_file, options)
      end

      private

      def run(manifest_file, options)
        config = load_and_merge_configs(manifest_file, options[:additional])

        exporter = SchemaExporter.new(
          config: config,
          output_path: options[:output],
          options: {
            annotations: options[:annotations],
            create_zip: options[:zip],
          },
        )

        exporter.export
      end

      # rubocop:disable Metrics/MethodLength
      def load_and_merge_configs(primary_path, additional_paths)
        primary_config = Expressir::SchemaManifest.from_file(primary_path)
        return primary_config unless additional_paths && !additional_paths.empty?

        # Load all additional manifests
        additional_configs = additional_paths.map do |path|
          unless File.exist?(path)
            raise Errno::ENOENT, "Specified additional manifest file " \
                                 "`#{path}` not found."
          end
          Expressir::SchemaManifest.from_file(path)
        end

        # Merge all configs into the primary
        merge_all_configs(primary_config, additional_configs)
      end
      # rubocop:enable Metrics/MethodLength

      def merge_all_configs(primary, additional_configs)
        # Collect all schemas from primary and all additional manifests
        all_schemas = primary.schemas.dup

        additional_configs.each do |config|
          all_schemas += config.schemas
        end

        Expressir::SchemaManifest.new(
          path: primary.path,
          schemas: all_schemas,
        )
      end

      def self.exit_on_failure?
        true
      end
    end
  end
end
