# frozen_string_literal: true

require "thor"
require_relative "../thor_ext"
require "fileutils"
require "expressir"
require "yaml"
require "securerandom"
require "glossarist"

module Suma
  module Cli
    # ExtractTerms command using Expressir to extract terms into the
    # Glossarist v2 format
    class ExtractTerms < Thor
      desc "extract_terms EXPRESS_FILE_PATH GLOSSARIST_OUTPUT_PATH",
           "Extract terms from EXPRESS files into the Glossarist v2 format"
      option :recursive, type: :boolean, default: false, aliases: "-r",
                         desc: "Extract terms from EXPRESS files under the " \
                               "specified path recursively"
      option :language_code, type: :string, default: "eng", aliases: "-l",
                             desc: "Language code for the Glossarist"

      def extract_terms(express_file_path, output_path) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
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

        unless File.exist?(output_path)
          FileUtils.mkdir_p(File.expand_path(output_path))
        end

        run(exp_files, output_path, language_code)
      end

      private

      def run(exp_files, output_path, language_code = "eng")
        exp_files.map do |exp_file|
          extract(exp_file, output_path, language_code)
        end
      end

      def extract(exp_file, output_path, language_code) # rubocop:disable Metrics/AbcSize
        puts "Processing EXPRESS file: #{exp_file}"
        repo = Expressir::Express::Parser.from_file(exp_file)
        schema = get_default_schema(repo)

        collection = build_managed_concept_collection(
          schema, language_code
        )

        output_data(collection, output_path, exp_file)
      end

      def output_data(collection, output_path, exp_file)
        puts "Saving collection to files in: #{File.expand_path(output_path)}"
        collection.save_to_files(File.expand_path(output_path))

        puts "Processing EXPRESS file: #{exp_file}...Done."
        collection
      end

      def build_managed_concept_collection(schema, language_code) # rubocop:disable Metrics/AbcSize
        managed_concept_data = Glossarist::ManagedConceptData.new
        managed_concept_data.id = get_identifier(schema)

        localized_concept_id = SecureRandom.uuid
        localized_concept = build_localized_concept(
          schema, language_code, localized_concept_id
        )

        managed_concept_data
          .localizations[localized_concept.language_code] = localized_concept

        managed_concept_data.localized_concepts = {
          localized_concept.language_code => localized_concept_id,
        }

        managed_concept = Glossarist::ManagedConcept.new
        managed_concept.uuid = SecureRandom.uuid
        managed_concept.data = managed_concept_data

        collection = Glossarist::ManagedConceptCollection.new
        collection.store(managed_concept)
        collection
      end

      def build_localized_concept(schema, language_code, localized_concept_id) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity
        localized_concept_data = Glossarist::ConceptData.new
        localized_concept_data.terms = get_terms(schema) || []
        localized_concept_data.definition = get_definitions(schema) || []
        localized_concept_data.notes = get_notes(schema) || []
        localized_concept_data.examples = get_examples(schema) || []
        localized_concept_data.language_code = language_code
        localized_concept_data.domain = get_domain(schema)
        localized_concept_data.sources = get_source_ref(schema) || []

        localized_concept = Glossarist::LocalizedConcept.new
        localized_concept.data = localized_concept_data

        localized_concept.uuid = localized_concept_id
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
        ref = remark_item&.remarks&.first

        if ref
          Glossarist::ConceptSource.new(
            type: "authoritative",
            origin: Glossarist::Citation.new(ref: ref),
          )
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
        schema_title = get_title(schema)
        if schema_title
          [
            Glossarist::Designation::Base.new(
              designation: schema_title,
              type: "expression",
              normative_status: "preferred",
            ),
          ]
        end
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
        [Glossarist::DetailedDefinition.new(content: definition)]
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
          Glossarist::DetailedDefinition.new(content: note)
        end
      end

      # get entities remark items with id `__example` as examples
      def get_examples(schema) # rubocop:disable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity,Metrics/AbcSize
        examples = schema.entities&.map do |entity|
          entity.remark_items&.select do |ri|
            ri.id == "__example"
          end&.map(&:remarks)
        end&.flatten&.compact

        examples&.map do |example|
          Glossarist::DetailedDefinition.new(content: example)
        end
      end

      def get_concept_filename(concept)
        identifier = concept["data"]["identifier"]
        "#{sanitize_string(identifier)}.yaml"
      end

      def sanitize_string(str)
        str.gsub(" ", "_").gsub("/", "_").gsub(":", "_")
      end
    end
  end
end
