# frozen_string_literal: true

require "thor"
require_relative "../utils"
require_relative "../link_validator"
require "expressir"

module Suma
  module Cli
    class ValidateLinks < Thor
      desc "extract_and_validate SCHEMAS_FILE DOCUMENTS_PATH [OUTPUT_FILE]",
           "Extract and validate express links without creating intermediate file"
      def extract_and_validate(schemas_file = "schemas-srl.yml",
                              documents_path = "documents",
                              output_file = "validation_results.txt")
        load_dependencies
        paths = prepare_file_paths(schemas_file, documents_path, output_file)

        schemas_config = load_schemas_config(paths[:schemas_file])
        exp_files = collect_schema_paths(schemas_config, paths[:schemas_file_rel])
        adoc_files = find_adoc_files(paths[:documents_path])

        all_files = adoc_files + exp_files
        display_file_counts(adoc_files, exp_files)

        links_by_file = extract_links(all_files)

        repo = load_express_schemas(schemas_config)
        index = SchemaIndex.new(repo)
        unresolved = LinkValidator.new(index).validate(links_by_file)

        write_validation_results(paths[:output_file], paths[:output_file_rel],
                                 unresolved, links_by_file)
      end

      private

      def load_dependencies
        require "expressir"
        require "ruby-progressbar"
        require "pathname"
      end

      def prepare_file_paths(schemas_file, documents_path, output_file)
        schemas_file_path = Pathname.new(schemas_file).expand_path
        documents_path_exp = Pathname.new(documents_path).expand_path
        output_file_path = Pathname.new(output_file).expand_path

        schemas_file_rel = Pathname.new(schemas_file_path).relative_path_from(Pathname.pwd).to_s
        documents_path_rel = Pathname.new(documents_path_exp).relative_path_from(Pathname.pwd).to_s
        output_file_rel = Pathname.new(output_file_path).relative_path_from(Pathname.pwd).to_s

        puts "Extracting and validating express links using schemas from #{schemas_file_rel}..."
        puts "Looking for documents in #{documents_path_rel}..."

        {
          schemas_file: schemas_file_path,
          schemas_file_rel: schemas_file_rel,
          documents_path: documents_path_exp,
          documents_path_rel: documents_path_rel,
          output_file: output_file_path,
          output_file_rel: output_file_rel,
        }
      end

      def load_schemas_config(schemas_file_path)
        schemas_config = Expressir::SchemaManifest.from_yaml(File.read(schemas_file_path))
        schemas_config.set_initial_path(schemas_file_path.to_s)
        schemas_config
      rescue StandardError => e
        raise Suma::Error, "Error loading schemas file: #{e.message}"
      end

      def collect_schema_paths(schemas_config, schemas_file_rel)
        exp_files = schemas_config.schemas.filter_map(&:path)
        puts "Found #{exp_files.size} EXPRESS schema files from #{schemas_file_rel}"
        exp_files
      end

      def find_adoc_files(documents_path)
        Dir.glob(documents_path.join("**", "*.adoc").to_s)
      end

      def display_file_counts(adoc_files, exp_files)
        puts "Found #{adoc_files.size} AsciiDoc files and #{exp_files.size} EXPRESS files"
      end

      def create_progress_bar(title, total)
        ProgressBar.create(
          title: title,
          total: total,
          format: "%t: [%B] %p%% %c/%C %e",
          progress_mark: "=",
          remainder_mark: " ",
          length: 80,
        )
      end

      def extract_links(files)
        links_by_file = {}
        link_count = 0

        progress = create_progress_bar("Processing files", files.size)

        files.each do |file|
          progress.increment
          begin
            content = File.read(file)
            express_links = content.scan(/<<express:([^,>]+)(?:,[^>]+)?>>/).flatten.uniq

            if express_links.any?
              links_by_file[file] = express_links
              link_count += express_links.size
            end
          rescue StandardError => e
            puts "\nWarning: Could not read file #{file}: #{e.message}"
          end
        end

        puts "\nExtracted #{link_count} unique express links from #{links_by_file.size} files"
        links_by_file
      end

      def load_express_schemas(schemas_config)
        schema_paths = {}
        schemas_config.schemas.each { |s| schema_paths[s.id] = s.path }

        puts "Loading #{schema_paths.size} EXPRESS schemas for validation..."

        loading_progress = create_progress_bar("Loading schemas", schema_paths.size)

        begin
          repo = Expressir::Express::Parser.from_files(schema_paths.values) do |filename, _schemas, error|
            loading_progress.increment
            puts "\nWarning: Error loading schema #{filename}: #{error.message}" if error
          end

          puts "Successfully loaded #{repo.schemas.size} schemas"
          repo
        rescue StandardError => e
          raise Suma::Error, "Error loading schemas: #{e.message}"
        end
      end

      def write_validation_results(output_file_path, output_file_rel,
  unresolved_links, links_by_file)
        total_links = links_by_file.values.sum(&:size)

        results = []
        results << "Validation complete. Checked #{total_links} links."

        if unresolved_links.empty?
          results << "✅ All links resolved successfully!"
        else
          results << "❌ Found #{unresolved_links.size} unresolved links:"
          unresolved_links.each do |issue|
            results << "#{issue.file}:#{issue.line} - <<express:#{issue.link}>> - #{issue.reason}"
          end
        end

        begin
          File.write(output_file_path, results.join("\n"))
          puts "Validation results written to #{output_file_rel}"
        rescue StandardError => e
          puts "Error writing to output file: #{e.message}"
          puts results
        end
      end
    end
  end
end
