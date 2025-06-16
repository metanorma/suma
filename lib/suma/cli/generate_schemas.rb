require "thor"
require_relative "../thor_ext"
require "fileutils"
require "yaml"

module Suma
  module Cli
    # GenerateSchemas command to generate Schemas YAML by Metanorma YAML
    class GenerateSchemas < Thor
      desc "generate_schemas METANORMA_YAML_FILE",
           "Generate Schemas YAML file from Metanorma YAML file"
      option :output, type: :string, required: false, aliases: "-o",
                      desc: "Write SCHEMAS YAML file (schemas-smrl-all.yml) " \
                            "in working directory or " \
                            "run in dry-run mode if not specified"
      option :exclude_paths, type: :string, default: nil, aliases: "-e",
                             desc: "Exclude schemas paths by pattern " \
                                   "(e.g. `*_lf.exp`)"

      def generate_schemas(metanorma_file_path) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
        metanorma_file_path = File.expand_path(metanorma_file_path)

        unless File.exist?(metanorma_file_path)
          raise Errno::ENOENT, "Specified file `#{metanorma_file_path}` " \
                               "not found."
        end

        unless File.file?(metanorma_file_path)
          raise ArgumentError, "Specified path `#{metanorma_file_path}` " \
                               "is not a file."
        end

        if ![".yaml", ".yml"].include?(File.extname(metanorma_file_path))
          raise ArgumentError, "Specified file `#{metanorma_file_path}` is " \
                               "not a YAML file."
        end

        if options[:output].nil?
          puts "Run in dry-run mode.\n" \
               "Please specify the option `output` " \
               "if you want to generate the output file."
        end

        run(
          metanorma_file_path,
          exclude_paths: options[:exclude_paths], output: options[:output],
        )
      end

      private

      def run(metanorma_file_path, exclude_paths: nil, output: nil)
        metanorma_data = load_yaml(metanorma_file_path)
        collection_files = metanorma_data["metanorma"]["source"]["files"]
        manifest_files = load_manifest_files(collection_files)
        all_schemas = load_project_schemas(manifest_files, exclude_paths)
        all_schemas["schemas"] = all_schemas["schemas"].sort.to_h
        output_data(all_schemas, output)
      end

      def output_data(all_schemas, output)
        if output
          path = output == "output" ? "schemas-smrl-all.yml" : output

          puts "Writing the Schemas YAML file to #{File.expand_path(path)}..."
          File.write(File.expand_path(path), all_schemas.to_yaml)
          puts "Writing the Schemas YAML file to #{File.expand_path(path)}..." \
               "Done"
        else
          puts all_schemas.to_yaml
          all_schemas.to_yaml
        end
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
