require "thor"
require_relative "../thor_ext"
require "fileutils"
require "yaml"

module Suma
  module Cli
    # GenerateSchemas command to generate Schemas YAML by Metanorma YAML
    class GenerateSchemas < Thor
      desc "generate_schemas METANORMA_MANIFEST_FILE SCHEMA_MANIFEST_FILE",
           "Generate EXPRESS schema manifest file from Metanorma site manifest"
      option :exclude_paths, type: :string, default: nil, aliases: "-e",
                             desc: "Exclude schemas paths by pattern " \
                                   "(e.g. `*_lf.exp`)"

      YAML_FILE_EXTENSIONS = [".yaml", ".yml"].freeze

      def generate_schemas(metanorma_manifest_file, schema_manifest_file) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
        metanorma_manifest_file = File.expand_path(metanorma_manifest_file)

        unless File.exist?(metanorma_manifest_file)
          raise Errno::ENOENT, "Specified file `#{metanorma_manifest_file}` " \
                               "not found."
        end

        unless File.file?(metanorma_manifest_file)
          raise ArgumentError, "Specified path `#{metanorma_manifest_file}` " \
                               "is not a file."
        end

        [metanorma_manifest_file, schema_manifest_file].each do |file|
          if !YAML_FILE_EXTENSIONS.include?(File.extname(file))
            raise ArgumentError, "Specified file `#{file}` is not a YAML file."
          end
        end

        run(
          metanorma_manifest_file, schema_manifest_file,
          exclude_paths: options[:exclude_paths]
        )
      end

      private

      def run(metanorma_manifest_file, schema_manifest_file, exclude_paths: nil)
        metanorma_data = load_yaml(metanorma_manifest_file)
        collection_files = metanorma_data["metanorma"]["source"]["files"]
        manifest_files = load_manifest_files(collection_files)
        all_schemas = load_project_schemas(manifest_files, exclude_paths)
        all_schemas["schemas"] = all_schemas["schemas"].sort.to_h
        output_data(all_schemas, schema_manifest_file)
      end

      def output_data(all_schemas, path)
        puts "Writing the Schemas YAML file to #{File.expand_path(path)}..."
        # debug use only
        # puts all_schemas.to_yaml
        File.write(File.expand_path(path), all_schemas.to_yaml)
        puts "Writing the Schemas YAML file to #{File.expand_path(path)}...Done"
      end

      def load_yaml(file_path)
        YAML.safe_load(
          File.read(file_path, encoding: "UTF-8"),
          permitted_classes: [Date, Time, Symbol],
          permitted_symbols: [],
          aliases: true,
        )
      end

      def load_manifest_files(collection_files)
        manifest_files = collection_files.map do |c|
          collection_data = load_yaml(c)
          collection_data["manifest"]["docref"].map { |docref| docref["file"] }
        end
        manifest_files.flatten
      end

      def load_project_schemas(manifest_files, exclude_paths) # rubocop:disable Metrics/AbcSize
        all_schemas = { "schemas" => {} }

        manifest_files.each do |file|
          # load schemas.yaml from the location of the collection.yml file
          schemas_file_path = File.expand_path(
            file.gsub("collection.yml", "schemas.yaml"),
          )
          unless File.exist?(schemas_file_path)
            puts "Schemas file not found: #{schemas_file_path}"
            next
          end

          schemas_data = load_yaml(schemas_file_path)

          if schemas_data["schemas"]
            schemas_data["schemas"] = fix_path(schemas_data, schemas_file_path)
            all_schemas["schemas"].merge!(schemas_data["schemas"])
          end

          if exclude_paths
            all_schemas["schemas"].delete_if do |_key, value|
              value["path"].match?(
                Regexp.new(exclude_paths.gsub("*", "(.*){1,999}")),
              )
            end
          end
        end

        all_schemas
      end

      def fix_path(schemas_data, schemas_file_path) # rubocop:disable Metrics/AbcSize
        depth = relative_depth(
          schemas_file_path, schemas_data["schemas"].values.first["path"]
        )

        if depth.negative?
          schemas_data["schemas"].each do |key, value|
            fixed_path = value["path"]
              .split(File::SEPARATOR)[(0 - depth)..]
              .join(File::SEPARATOR)

            { key => value.merge!("path" => fixed_path) }
          end
        end

        schemas_data["schemas"]
      end

      def relative_depth(parent_path, child_path)
        parent_chunks = parent_path.split(File::SEPARATOR).reject(&:empty?)
        child_chunks = child_path.split(File::SEPARATOR).reject(&:empty?)
        (child_chunks.length - parent_chunks.length)
      end
    end
  end
end
