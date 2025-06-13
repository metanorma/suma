# frozen_string_literal: true

require "thor"
require_relative "../thor_ext"
require "fileutils"
require "expressir"
require "yaml"
require "securerandom"

module Suma
  module Cli
    # ExtractTerms command using Expressir to extract terms into the
    # Glossarist v2 format
    class ExtractTerms < Thor
      desc "extract_terms EXPRESS_FILE_PATH",
           "Extract terms from EXPRESS files into the Glossarist v2 format"
      option :recursive, type: :boolean, default: false, aliases: "-r",
                         desc: "Extract terms from EXPRESS files under the " \
                               "specified path recursively"
      option :output, type: :string, required: false, aliases: "-o",
                      desc: "Output folder for the extracted terms or " \
                            "run in dry-run mode if not specified"
      option :language_code, type: :string, default: "eng", aliases: "-l",
                             desc: "Language code for the Glossarist"

      def extract_terms(express_file_path) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
        output = options[:output]
        language_code = options[:language_code]

        if File.file?(express_file_path)
          unless File.exist?(express_file_path)
            raise Errno::ENOENT, "Specified EXPRESS file " \
                                 "`#{express_file_path}` not found."
          end

          if File.extname(express_file_path) != ".exp"
            raise ArgumentError, "Specified file `#{express_file_path}` is " \
                                 "not an EXPRESS file."
          end

          exp_files = [express_file_path]
        elsif options[:recursive]
          exp_files = Dir.glob("#{express_file_path}/**/*.exp")
        else
          exp_files = Dir.glob("#{express_file_path}/*.exp")
        end

        if exp_files.empty?
          raise Errno::ENOENT, "No EXPRESS files found in " \
                               "`#{express_file_path}`."
        end

        if output.nil?
          puts "Run in dry-run mode. " \
               "Please specify the output folder if you want save the results."
        end
        if output && File.exist?(output) && !File.directory?(output)
          raise Errno::ENOTDIR, "Specified output path `#{output}` is not a " \
                                "directory."
        end

        run(exp_files, output, language_code)
      end

      private

      def run(exp_files, output, language_code = "eng")
        exp_files.map do |exp_file|
          extract(exp_file, output, language_code)
        end
      end

      def extract(file, output, language_code) # rubocop:disable Metrics/AbcSize
        puts "Processing EXPRESS file: #{file}"
        repo = Expressir::Express::Parser.from_file(file)
        schema = get_default_schema(repo)

        localized_concept_id = SecureRandom.uuid
        localized_concept = build_localized_concept(
          schema, language_code
        )

        concept = build_concept(
          schema, language_code, localized_concept_id
        )

        output_data(file, concept, localized_concept,
                    localized_concept_id, output)
      end

      def output_data(file, concept, localized_concept,
        localized_concept_id, output)
        result = { "source_file" => file }

        if output
          write_concept(concept, output)
          write_localized_concept(
            localized_concept_id, localized_concept, output
          )
        else
          concept_filename = get_concept_filename(concept)
          puts "Dry-run mode:\n" \
               "Would write to concept file: #{concept_filename}\n" \
               "and localized_concept file: #{localized_concept_id}.yaml"

          result = {
            "source_file" => file,
            "concept" => concept,
            "localized_concept" => localized_concept,
          }

          # Debug: show output on screen
          puts result.to_yaml

          result
        end

        puts "Processing EXPRESS file: #{file}...Done."
        result
      end

      def build_concept(schema, language_code, localized_concept_id) # rubocop:disable Metrics/AbcSize
        concept = {}
        concept["id"] = SecureRandom.uuid
        concept["data"] = {}
        concept["data"]["identifier"] = get_identifier(schema)
        concept["data"]["localized_concepts"] = {
          language_code => localized_concept_id,
        }

        concept
      end

      def build_localized_concept(schema, language_code) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity
        localized_concept = {}
        localized_concept["data"] = {}
        localized_concept["data"]["terms"] = get_terms(schema) || []
        localized_concept["data"]["definition"] = get_definitions(schema) || []
        localized_concept["data"]["notes"] = get_notes(schema) || []
        localized_concept["data"]["examples"] = get_examples(schema) || []
        localized_concept["data"]["language_code"] = language_code
        localized_concept["data"]["domain"] = get_domain(schema) || []
        localized_concept["data"]["source"] = get_source_ref(schema) || []

        localized_concept
      end

      def get_default_schema(repo)
        repo.schemas.first
      end

      def get_identifier(schema)
        remark_item = schema.remark_items.find do |s|
          s.id == "__identifier"
        end
        remark_item.remarks.first || SecureRandom.uuid
      end

      def get_title(schema)
        remark_item = schema.remark_items.find do |s|
          s.id == "__title"
        end
        remark_item.remarks.first
      end

      def get_source_ref(schema)
        remark_item = schema.remark_items.find do |s|
          s.id == "__published_in"
        end
        ref = remark_item.remarks.first

        if ref
          [
            {
              "type" => "authoritative",
              "origin" => { "ref" => ref },
            },
          ]
        end
      end

      def get_domain(schema)
        prefix = module?(schema) ? "application module" : "resource"
        "#{prefix}: #{schema.id}"
      end

      def module?(schema)
        remark_item = schema.remark_items.find do |s|
          s.id == "__schema_file"
        end

        File.basename(remark_item.remarks.first, ".*") == "module"
      end

      def arm?(schema_id)
        schema_id.end_with?("_arm")
      end

      def get_terms(schema)
        term = {}

        term["type"] = "expression"
        term["normative_status"] = "preferred"
        term["designation"] = get_title(schema)

        [term]
      end

      def get_schema_type(schema)
        return "resource" if !module?(schema)

        return "arm" if arm?(schema.id)

        "min"
      end

      def get_definitions(schema)
        type = get_schema_type(schema)
        subtype = get_subtype_of(schema)

        represent_str = "that represents the #{get_title(schema)} {{entity}}"
        if subtype
          represent_str = "that is a type of #{subtype} #{represent_str}"
        end

        definition = case type
                     when "arm"
                       "{{application object}} #{represent_str}"
                     else
                       "{{entity data type}} #{represent_str}"
                     end
        [{ "content" => definition }]
      end

      def get_subtype_of(schema)
        schema.entities.first&.subtype_of&.first&.id # rubocop:disable Style/SafeNavigationChainLength
      end

      # get entities remarks and remark items with id `__note` as notes
      def get_notes(schema) # rubocop:disable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity,Metrics/AbcSize
        notes = schema.entities&.map do |entity|
          [
            entity.remarks,
            entity.remark_items&.select do |ri|
              ri.id == "__note"
            end&.map(&:remarks),
          ]
        end&.flatten&.compact

        notes&.map do |note|
          { "content" => note }
        end
      end

      # get entities remark items with id `__example` as examples
      def get_examples(schema) # rubocop:disable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
        examples = schema.entities&.map do |entity|
          entity.remark_items&.select do |ri|
            ri.id == "__example"
          end&.map(&:remarks)
        end&.flatten&.compact

        examples&.map do |example|
          { "content" => example }
        end
      end

      def get_concept_filename(concept)
        identifier = concept["data"]["identifier"]
        "#{sanitize_string(identifier)}.yaml"
      end

      def write_concept(concept, output)
        write_file(
          concept.to_yaml, output, "concept", get_concept_filename(concept)
        )
      end

      def write_localized_concept(localized_concept_id, localized_concept,
                                  output)
        filename = "#{localized_concept_id}.yaml"

        write_file(localized_concept.to_yaml,
                   output, "localized_concept",
                   filename, type: "localized_concept")

        localized_concept_id
      end

      def write_file(content, output, join_path, filename, type: "concept")
        path = File.join(output, join_path, filename)
        puts "Writing to #{type} file: #{path}..."

        # Ensure the output directory exists
        FileUtils.mkdir_p(File.join(output, join_path))

        File.write(path, content)
        puts "Writing to #{type} file: #{path}...Done."
      end

      def sanitize_string(str)
        str.gsub(" ", "_").gsub("/", "_").gsub(":", "_")
      end
    end
  end
end
