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
      desc "extract_terms SCHEMA_MANIFEST_FILE GLOSSARIST_OUTPUT_PATH",
           "Extract terms from SCHEMA_MANIFEST_FILE into " \
           "Glossarist v2 format"
      option :language_code, type: :string, default: "eng", aliases: "-l",
                             desc: "Language code for the Glossarist"

      YAML_FILE_EXTENSIONS = [".yaml", ".yml"].freeze
      CUSTOM_LOCALITY_NAMES = %w(version schema).freeze

      def extract_terms(schema_manifest_file, output_path) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
        language_code = options[:language_code]
        schema_manifest_file = File.expand_path(schema_manifest_file)

        if File.file?(schema_manifest_file)
          unless File.exist?(schema_manifest_file)
            raise Errno::ENOENT, "Specified SCHEMA_MANIFEST_FILE " \
                                 "`#{schema_manifest_file}` not found."
          end

          if !YAML_FILE_EXTENSIONS.include?(File.extname(schema_manifest_file))
            raise ArgumentError, "Specified SCHEMA_MANIFEST_FILE " \
                                 "`#{schema_manifest_file}` " \
                                 "is not a YAML file."
          end
        end

        run(schema_manifest_file, output_path, language_code)
      end

      private

      def run(schema_manifest_file, output_path, language_code = "eng")
        exp_files = get_exp_files(schema_manifest_file)

        exp_files.map do |exp_file|
          extract(exp_file, output_path, language_code)
        end
      end

      def get_exp_files(schema_manifest_file)
        data = YAML.safe_load(
          File.read(schema_manifest_file, encoding: "UTF-8"),
          permitted_classes: [Date, Time, Symbol],
          permitted_symbols: [],
          aliases: true,
        )

        paths = data["schemas"].values.filter_map { |v| v["path"] }

        if paths.empty?
          raise Errno::ENOENT, "No EXPRESS files found in " \
                               "`#{schema_manifest_file}`."
        end

        # resolve paths relative to the directory of the schema manifest file
        paths.map do |path|
          File.expand_path(path, File.dirname(schema_manifest_file))
        end
      end

      def extract(exp_file, output_path, language_code) # rubocop:disable Metrics/AbcSize
        exp_file_path_rel = Pathname.new(exp_file)
          .relative_path_from(Pathname.getwd)
        puts "Processing EXPRESS file: #{exp_file_path_rel}"
        repo = Expressir::Express::Parser.from_file(exp_file)
        schema = get_default_schema(repo)

        collection = build_managed_concept_collection(
          schema, language_code
        )

        output_data(collection, output_path, exp_file)
      end

      def output_data(collection, output_path, exp_file)
        exp_file_path_rel = Pathname.new(exp_file)
          .relative_path_from(Pathname.getwd)
        unless File.exist?(output_path)
          FileUtils.mkdir_p(File.expand_path(output_path))
        end

        puts "Saving collection to files in: #{output_path}"
        collection.save_to_files(File.expand_path(output_path))

        puts "Processing EXPRESS file: #{exp_file_path_rel}...Done."
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
        schema_domain = get_domain(schema)

        localized_concept_data = Glossarist::ConceptData.new
        localized_concept_data.terms = get_terms(schema) || []
        localized_concept_data.definition = get_definitions(schema) || []
        localized_concept_data.notes = get_notes(schema, schema_domain) || []
        localized_concept_data.examples = get_examples(schema,
                                                       schema_domain) || []
        localized_concept_data.language_code = language_code
        localized_concept_data.domain = schema_domain
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

      def get_source_ref(schema) # rubocop:disable Metrics/AbcSize
        remark_item = schema.remark_items.find do |s|
          s.id == "__published_in"
        end
        ref = remark_item&.remarks&.first

        if ref
          origin = Glossarist::Citation.new(ref: ref.split("-").first.strip)
          custom_locality = get_custom_locality(schema)
          unless custom_locality.empty?
            origin.custom_locality = custom_locality
          end

          Glossarist::ConceptSource.new(
            type: "authoritative",
            origin: origin,
          )
        end
      end

      def get_custom_locality(schema)
        schema.version.items.filter_map do |i|
          if CUSTOM_LOCALITY_NAMES.include?(i.name)
            Glossarist::CustomLocality.new(name: i.name, value: i.value)
          end
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
      def get_notes(schema, schema_domain) # rubocop:disable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity,Metrics/AbcSize
        notes = schema.entities&.map do |entity|
          [
            entity.remarks,
            entity.remark_items&.select do |ri|
              ri.id == "__note"
            end&.map(&:remarks),
          ]
        end&.flatten&.compact

        notes&.map do |note|
          Glossarist::DetailedDefinition.new(
            content: convert_express_xref(note, schema_domain),
          )
        end
      end

      # get entities remark items with id `__example` as examples
      def get_examples(schema, schema_domain) # rubocop:disable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity,Metrics/AbcSize
        examples = schema.entities&.map do |entity|
          entity.remark_items&.select do |ri|
            ri.id == "__example"
          end&.map(&:remarks)
        end&.flatten&.compact

        examples&.map do |example|
          Glossarist::DetailedDefinition.new(
            content: convert_express_xref(example, schema_domain),
          )
        end
      end

      def convert_express_xref(content, schema_domain)
        content.gsub(/<<express:(.*),(.*)>>/) do
          "{{<#{schema_domain}>" \
            "#{Regexp.last_match(1).split('.').last},#{Regexp.last_match(2)}}}"
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
