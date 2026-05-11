# frozen_string_literal: true

require "yaml"
require "pathname"
require_relative "utils"

module Suma
  class SchemaManifestGenerator
    YAML_FILE_EXTENSIONS = [".yaml", ".yml"].freeze

    def initialize(metanorma_manifest_file, schema_manifest_file, exclude_paths: nil)
      @metanorma_manifest_file = File.expand_path(metanorma_manifest_file)
      @schema_manifest_file = schema_manifest_file
      @exclude_paths = exclude_paths
    end

    def generate
      validate_inputs
      metanorma_data = load_yaml(@metanorma_manifest_file)
      collection_files = metanorma_data["metanorma"]["source"]["files"]
      manifest_files = load_manifest_files(collection_files)
      all_schemas = load_project_schemas(manifest_files)
      all_schemas["schemas"] = all_schemas["schemas"].sort.to_h
      write_output(all_schemas)
    end

    private

    def validate_inputs
      raise Errno::ENOENT, "Specified file `#{@metanorma_manifest_file}` not found." unless File.exist?(@metanorma_manifest_file)

      raise ArgumentError, "Specified path `#{@metanorma_manifest_file}` is not a file." unless File.file?(@metanorma_manifest_file)

      [@metanorma_manifest_file, @schema_manifest_file].each do |file|
        unless YAML_FILE_EXTENSIONS.include?(File.extname(file))
          raise ArgumentError, "Specified file `#{file}` is not a YAML file."
        end
      end
    end

    def load_yaml(file_path)
      YAML.safe_load(File.read(file_path, encoding: "UTF-8"), aliases: true)
    end

    def load_manifest_files(collection_files)
      collection_files.map do |c|
        collection_data = load_yaml(c)
        collection_data["manifest"]["docref"].map { |docref| docref["file"] }
      end.flatten
    end

    def load_project_schemas(manifest_files)
      all_schemas = { "schemas" => {} }

      manifest_files.each do |file|
        schemas_file_path = File.expand_path(file.gsub("collection.yml", "schemas.yaml"))

        unless File.exist?(schemas_file_path)
          Utils.log "Schemas file not found: #{schemas_file_path}"
          next
        end

        schemas_data = load_yaml(schemas_file_path)

        if schemas_data["schemas"]
          schemas_data["schemas"] = fix_path(schemas_data, schemas_file_path)
          all_schemas["schemas"].merge!(schemas_data["schemas"])
        end

        if @exclude_paths
          all_schemas["schemas"].delete_if do |_key, value|
            value["path"].match?(
              Regexp.new(@exclude_paths.gsub("*", "(.*){1,999}")),
            )
          end
        end
      end

      all_schemas
    end

    def fix_path(schemas_data, schemas_file_path)
      schema_manifest_path = File.expand_path(@schema_manifest_file, Dir.pwd)

      schemas_data["schemas"].each do |key, value|
        path_in_schema = File.expand_path(value["path"], File.dirname(schemas_file_path))

        fixed_path = Pathname.new(path_in_schema).relative_path_from(
          Pathname.new(File.dirname(schema_manifest_path)),
        )

        { key => value.merge!("path" => fixed_path.to_s) }
      end

      schemas_data["schemas"]
    end

    def write_output(all_schemas)
      output_path = File.expand_path(@schema_manifest_file)
      Utils.log "Writing the Schemas YAML file to #{output_path}..."
      File.write(output_path, all_schemas.to_yaml)
      Utils.log "Writing the Schemas YAML file to #{output_path}...Done"
    end
  end
end
