# frozen_string_literal: true

require "thor"
require_relative "../utils"
require "expressir"

module Suma
  module Cli
    # ValidateLinks command for managing EXPRESS links
    class ValidateLinks < Thor
      desc "extract_and_validate SCHEMAS_FILE DOCUMENTS_PATH [OUTPUT_FILE]",
           "Extract and validate express links without creating intermediate file"
      def extract_and_validate(schemas_file = "schemas-srl.yml",
                              documents_path = "documents",
                              output_file = "validation_results.txt")
        load_dependencies
        paths = prepare_file_paths(schemas_file, documents_path, output_file)

        # Load schemas and extract links
        schemas_config = load_schemas_config(paths[:schemas_file])
        exp_files = collect_schema_paths(schemas_config,
                                         paths[:schemas_file_rel])
        adoc_files = find_adoc_files(paths[:documents_path])

        all_files = adoc_files + exp_files
        display_file_counts(adoc_files, exp_files)

        # Extract links from files
        links_by_file = extract_links(all_files)

        # Validate links against schemas
        repo = load_express_schemas(schemas_config)
        unresolved_links = validate_links(links_by_file, repo)

        # Generate and output results
        write_validation_results(paths[:output_file], paths[:output_file_rel],
                                 unresolved_links, links_by_file)
      end

      private

      # Load all required dependencies for link validation
      def load_dependencies
        # Lazy-load dependencies only when this command is actually used
        require "expressir"
        require "ruby-progressbar"
        require "pathname"
      end

      # Prepare and normalize all file paths needed for the operation
      def prepare_file_paths(schemas_file, documents_path, output_file)
        # Convert to absolute paths
        schemas_file_path = Pathname.new(schemas_file).expand_path
        documents_path = Pathname.new(documents_path).expand_path
        output_file_path = Pathname.new(output_file).expand_path

        # Store relative paths for display
        schemas_file_rel = Pathname.new(schemas_file_path).relative_path_from(Pathname.pwd).to_s
        documents_path_rel = Pathname.new(documents_path).relative_path_from(Pathname.pwd).to_s
        output_file_rel = Pathname.new(output_file_path).relative_path_from(Pathname.pwd).to_s

        puts "Extracting and validating express links using schemas from #{schemas_file_rel}..."
        puts "Looking for documents in #{documents_path_rel}..."

        {
          schemas_file: schemas_file_path,
          schemas_file_rel: schemas_file_rel,
          documents_path: documents_path,
          documents_path_rel: documents_path_rel,
          output_file: output_file_path,
          output_file_rel: output_file_rel,
        }
      end

      # Load and initialize the schemas configuration
      def load_schemas_config(schemas_file_path)
        schemas_config = Expressir::SchemaManifest.from_yaml(File.read(schemas_file_path))
        # Ensure the config is initialized with the correct path to resolve relative paths
        schemas_config.set_initial_path(schemas_file_path.to_s)
        schemas_config
      rescue StandardError => e
        puts "Error loading schemas file: #{e.message}"
        exit(1)
      end

      # Collect paths to all schema files from the config
      def collect_schema_paths(schemas_config, schemas_file_rel)
        exp_files = []
        schemas_config.schemas.each do |schema|
          exp_files << schema.path if schema.path
        end

        puts "Found #{exp_files.size} EXPRESS schema files from #{schemas_file_rel}"
        exp_files
      end

      # Find all AsciiDoc files in the specified path
      def find_adoc_files(documents_path)
        Dir.glob(documents_path.join("**", "*.adoc").to_s)
      end

      # Display counts of discovered files
      def display_file_counts(adoc_files, exp_files)
        puts "Found #{adoc_files.size} AsciiDoc files and #{exp_files.size} EXPRESS files"
      end

      # Create a standardized progress bar
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

      # Extract EXPRESS links from all files
      def extract_links(files)
        links_by_file = {}
        link_count = 0

        progress = create_progress_bar("Processing files", files.size)

        files.each do |file|
          progress.increment
          begin
            content = File.read(file)
            # Extract links while ignoring text after comma
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

      # Load all EXPRESS schemas for validation
      def load_express_schemas(schemas_config)
        # Get all schema paths for validation
        schema_paths = {}
        schemas_config.schemas.each do |schema|
          schema_paths[schema.id] = schema.path
        end

        puts "Loading #{schema_paths.size} EXPRESS schemas for validation..."

        # Setup progress bar for schema loading
        loading_progress = create_progress_bar("Loading schemas",
                                               schema_paths.size)

        # Try to load all schemas with progress tracking
        begin
          repo = Expressir::Express::Parser.from_files(schema_paths.values) do |filename, _schemas, error|
            loading_progress.increment
            if error
              puts "\nWarning: Error loading schema #{filename}: #{error.message}"
            end
          end

          puts "Successfully loaded #{repo.schemas.size} schemas"
          repo
        rescue StandardError => e
          puts "Error loading schemas: #{e.message}"
          exit(1)
        end
      end

      # Validate all links against loaded schemas
      def validate_links(links_by_file, repo)
        unresolved_links = []
        total_links = links_by_file.values.sum(&:size)

        progress = create_progress_bar("Validating links", total_links)

        links_by_file.each do |file, links|
          validate_file_links(file, links, repo, progress, unresolved_links)
        end

        unresolved_links
      end

      # Validate links in a specific file
      def validate_file_links(file, links, repo, progress, unresolved_links)
        file_content = File.read(file)
        file_lines = file_content.lines

        links.each do |link|
          progress.increment
          line_idx = find_link_line(file_lines, link)
          next unless line_idx

          # Parse link (schema only, schema.element, or schema.element.path)
          parts = link.split(".")

          if parts.size == 1
            validate_schema_only_link(parts[0], repo, file, line_idx, link,
                                      unresolved_links)
          else
            validate_schema_element_link(parts, repo, file, line_idx, link,
                                         unresolved_links)
          end
        end
      rescue StandardError => e
        puts "Warning: Error processing file #{file}: #{e.message}"
      end

      # Find the line where a link appears in the file
      def find_link_line(file_lines, link)
        file_lines.each_with_index do |line, idx|
          # Match both with and without comma text
          if /<<express:#{Regexp.escape(link)}(?:,[^>]+)?>>/.match?(line)
            return idx
          end
        end
        nil
      end

      # Validate a link that only references a schema
      def validate_schema_only_link(schema_name, repo, file, line_idx, link,
  unresolved_links)
        # Check if schema exists
        schema = repo.schemas.find do |s|
          s.id.downcase == schema_name.downcase
        end

        if !schema
          unresolved_links << {
            file: file,
            line: line_idx + 1,
            link: link,
            reason: "Schema '#{schema_name}' not found",
          }
        end
      end

      # Validate a link with schema.element or deeper paths
      def validate_schema_element_link(parts, repo, file, line_idx, link,
  unresolved_links)
        schema_name = parts[0]
        element_name = parts[1]

        # Check if schema exists
        schema = repo.schemas.find do |s|
          s.id.downcase == schema_name.downcase
        end

        if !schema
          unresolved_links << {
            file: file,
            line: line_idx + 1,
            link: link,
            reason: "Schema '#{schema_name}' not found",
          }
          return
        end

        # Find the element in the schema
        element = find_schema_element(schema, element_name)

        if !element
          unresolved_links << {
            file: file,
            line: line_idx + 1,
            link: link,
            reason: "Element '#{element_name}' not found in schema '#{schema_name}'",
          }
          return
        end

        # If we have more than 2 parts, validate the deeper path
        if parts.size > 2
          validation_error = validate_deep_path(schema, element, parts[2..],
                                                file, line_idx, link)
          unresolved_links << validation_error if validation_error
        end
      end

      # Find an element in a schema by name
      def find_schema_element(schema, element_name)
        # Try to find element in various collections
        element_collections = [
          schema.entities,
          schema.types,
          schema.constants,
          schema.functions,
          schema.rules,
          schema.procedures,
          schema.subtype_constraints,
        ]

        element_collections.each do |collection|
          element = collection&.find do |e|
            e.id.downcase == element_name.downcase
          end
          return element if element
        end

        nil
      end

      # Validate deeper paths in a link (schema.element.path.subpath)
      def validate_deep_path(schema, element, path_parts, file, line_idx,
  full_link)
        current_element = element
        current_path = "#{schema.id}.#{element.id}"

        # Process each part of the path
        path_parts.each do |part|
          # The validation logic depends on the type of current element
          case current_element
          when Expressir::Express::Entity
            # For entities, check attributes
            attribute = current_element.attributes&.find do |a|
              a.id.downcase == part.downcase
            end

            unless attribute
              return {
                file: file,
                line: line_idx + 1,
                link: full_link,
                reason: "Attribute '#{part}' not found in entity '#{current_path}'",
              }
            end

            current_element = attribute
            current_path += ".#{part}"

          when Expressir::Express::Type
            # For types, validation depends on type kind
            if current_element.respond_to?(:base_type) && current_element.base_type
              # For derived types, find the base type
              base_type = find_base_type(schema, current_element.base_type)

              unless base_type
                return {
                  file: file,
                  line: line_idx + 1,
                  link: full_link,
                  reason: "Base type not found for '#{current_path}'",
                }
              end

              # Continue validation using base type
              current_element = base_type

            elsif current_element.respond_to?(:elements) && current_element.elements
              # For enum types, check enum values
              enum_value = current_element.elements.find do |e|
                e.id.downcase == part.downcase
              end

              unless enum_value
                return {
                  file: file,
                  line: line_idx + 1,
                  link: full_link,
                  reason: "Enumeration value '#{part}' not found in type '#{current_path}'",
                }
              end

              current_element = enum_value
              current_path += ".#{part}"

            else
              # For other types, we can't navigate deeper
              return {
                file: file,
                line: line_idx + 1,
                link: full_link,
                reason: "Cannot navigate deeper from type '#{current_path}'",
              }
            end

          else
            # For other element types, navigation is not supported
            return {
              file: file,
              line: line_idx + 1,
              link: full_link,
              reason: "Cannot navigate deeper from '#{current_path}'",
            }
          end
        end

        # If we've processed all parts without returning an error, path is valid
        nil
      end

      # Find a base type in a schema
      def find_base_type(schema, type_ref)
        # Skip built-in types
        return nil if %w[INTEGER REAL STRING BOOLEAN NUMBER BINARY
                         LOGICAL].include?(type_ref.to_s.upcase)

        # Find the referenced type in the schema
        if type_ref.is_a?(String)
          find_schema_element(schema, type_ref)
        elsif type_ref.respond_to?(:id)
          # It's already a type object
          type_ref
        else
          nil
        end
      end

      # Write validation results to the output file
      def write_validation_results(output_file_path, output_file_rel,
  unresolved_links, links_by_file)
        total_links = links_by_file.values.sum(&:size)

        # Prepare results for output
        results = []
        results << "Validation complete. Checked #{total_links} links."

        if unresolved_links.empty?
          results << "✅ All links resolved successfully!"
        else
          results << "❌ Found #{unresolved_links.size} unresolved links:"
          unresolved_links.each do |issue|
            results << "#{issue[:file]}:#{issue[:line]} - <<express:#{issue[:link]}>> - #{issue[:reason]}"
          end
        end

        # Write results to output file
        begin
          File.write(output_file_path, results.join("\n"))
          puts "Validation results written to #{output_file_rel}"
        rescue StandardError => e
          puts "Error writing to output file: #{e.message}"
          # Still print results to console as fallback
          puts results
        end
      end
    end
  end
end
