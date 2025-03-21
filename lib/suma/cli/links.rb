# frozen_string_literal: true

require "thor"
require_relative "../utils"

module Suma
  # Links command for managing EXPRESS links
  class Links < Thor
    desc "extract_and_validate SCHEMAS_FILE DOCUMENTS_PATH [OUTPUT_FILE]",
         "Extract and validate express links without creating intermediate file"
    def extract_and_validate(schemas_file = "schemas-srl.yml",
                            documents_path = "documents",
                            output_file = "validation_results.txt")
      # Lazy-load dependencies only when this command is actually used
      require "expressir"
      require "ruby-progressbar"
      require_relative "../schema_config"

      require "pathname"

      # Convert to absolute paths
      schemas_file_path = Pathname.new(schemas_file).expand_path
      documents_path = Pathname.new(documents_path).expand_path
      output_file_path = Pathname.new(output_file).expand_path

      # Use relative paths for display
      schemas_file_rel = Pathname.new(schemas_file_path).relative_path_from(Pathname.pwd).to_s
      documents_path_rel = Pathname.new(documents_path).relative_path_from(Pathname.pwd).to_s
      output_file_rel = Pathname.new(output_file_path).relative_path_from(Pathname.pwd).to_s

      puts "Extracting and validating express links using schemas from #{schemas_file_rel}..."
      puts "Looking for documents in #{documents_path_rel}..."

      # Load schemas using Suma's SchemaConfig
      begin
        schemas_config = Suma::SchemaConfig::Config.from_yaml(IO.read(schemas_file_path))
        # Ensure the config is initialized with the correct path to resolve relative paths
        schemas_config.set_initial_path(schemas_file_path.to_s)
      rescue StandardError => e
        puts "Error loading schemas file: #{e.message}"
        exit(1)
      end

      # Get schema paths from the schemas config
      exp_files = []
      schemas_config.schemas.each do |schema|
        exp_files << schema.path if schema.path
      end

      puts "Found #{exp_files.size} EXPRESS schema files from #{schemas_file_rel}"

      # Find all .adoc files in the specified documents path
      adoc_files = Dir.glob(documents_path.join("**", "*.adoc").to_s)
      all_files = adoc_files + exp_files

      puts "Found #{adoc_files.size} AsciiDoc files and #{exp_files.size} EXPRESS files"

      # Extract links organized by filename
      links_by_file = {}
      link_count = 0

      # Setup progress bar
      progress = ProgressBar.create(
        title: "Processing files",
        total: all_files.size,
        format: "%t: [%B] %p%% %c/%C %e",
        progress_mark: "=",
        remainder_mark: " ",
        length: 80,
      )

      all_files.each do |file|
        # Update progress bar
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

      # Get all schema paths for validation
      schema_paths = {}
      schemas_config.schemas.each do |schema|
        schema_paths[schema.id] = schema.path
      end

      puts "Loading #{schema_paths.size} EXPRESS schemas for validation..."

      # Try to load all schemas at once
      repo = nil
      begin
        repo = Expressir::Express::Parser.from_files(schema_paths.values)
        puts "Successfully loaded #{repo.schemas.size} schemas"
      rescue StandardError => e
        puts "Error loading schemas: #{e.message}" # Added error message output
        exit(1)
      end

      # Check each link
      unresolved_links = []
      total_links = 0

      # Get total number of links for progress bar
      links_by_file.each do |_file, links|
        total_links += links.size
      end

      # Setup progress bar for validation
      progress = ProgressBar.create(
        title: "Validating links",
        total: total_links,
        format: "%t: [%B] %p%% %c/%C %e",
        progress_mark: "=",
        remainder_mark: " ",
        length: 80,
      )

      links_by_file.each do |file, links|
        file_content = File.read(file)
        file_lines = file_content.lines

        links.each do |link|
          # Update progress
          progress.increment
          # Find the line number(s) where this link appears
          # Need to handle different formats including ones with comma text
          line_idx = nil
          file_lines.each_with_index do |line, idx|
            # Match both with and without comma text
            if /<<express:#{Regexp.escape(link)}(?:,[^>]+)?>>/.match?(line)
              line_idx = idx
              break
            end
          end

          next unless line_idx

          # Parse link (schema only, schema.element, or schema.element.path)
          parts = link.split(".")

          # Handle schema-only case
          if parts.size == 1
            schema_name = parts[0]

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
            next
          end

          # For schema.element or schema.element.path, validate schema and first element
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
            next
          end

          # Check if element exists in the schema
          element_found = false

          # Check entities
          if schema.entities&.any? do |e|
            e.id.downcase == element_name.downcase
          end
            element_found = true
          # Check types
          elsif schema.types&.any? do |t|
            t.id.downcase == element_name.downcase
          end
            element_found = true
          # Check constants
          elsif schema.constants&.any? do |c|
            c.id.downcase == element_name.downcase
          end
            element_found = true
          # Check functions
          elsif schema.functions&.any? do |f|
            f.id.downcase == element_name.downcase
          end
            element_found = true
          # Check rules
          elsif schema.rules&.any? do |r|
            r.id.downcase == element_name.downcase
          end
            element_found = true
          # Check procedures
          elsif schema.procedures&.any? do |p|
            p.id.downcase == element_name.downcase
          end
            element_found = true
          # Check subtype constraints
          elsif schema.subtype_constraints&.any? do |s|
            s.id.downcase == element_name.downcase
          end
            element_found = true
          end

          unless element_found
            unresolved_links << {
              file: file,
              line: line_idx + 1,
              link: link,
              reason: "Element '#{element_name}' not found in schema '#{schema_name}'",
            }
          end
        end
      rescue StandardError => e
        puts "Warning: Error processing file #{file}: #{e.message}"
      end

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
