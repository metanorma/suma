# frozen_string_literal: true

require "fileutils"
require_relative "utils"
require "expressir"
require "glossarist"

module Suma
  class TermExtractor
    REDUNDANT_NOTE_REGEX =
      %r{
        ^An?                   # Starts with "A" or "An"
        \s.*?\sis\sa\stype\sof # Text followed by "is a type of"
        (\sa|\san)?            # Optional " a" or " an"
        \s\{\{[^\}]*\}\}       # Text in double curly braces
        \s*?\.?$               # Optional whitespace and period at the end
      }x

    def initialize(schema_manifest_file, output_path, language_code: "eng")
      @schema_manifest_file = File.expand_path(schema_manifest_file)
      @output_path = output_path
      @language_code = language_code
    end

    def call
      get_exp_files.map do |exp_file|
        extract(exp_file)
      end
    end

    private

    def get_exp_files
      config = Expressir::SchemaManifest.from_file(@schema_manifest_file)
      paths = config.schemas.map(&:path)

      if paths.empty?
        raise Errno::ENOENT, "No EXPRESS files found in `#{@schema_manifest_file}`."
      end

      paths
    end

    def extract(exp_file)
      exp_path_rel = Pathname.new(exp_file).relative_path_from(Pathname.getwd)
      Utils.log "Building terms: #{exp_path_rel}"

      repo = Expressir::Express::Parser.from_file(exp_file)
      schema = repo.schemas.first

      raise Error, "Schema must have an associated file" unless schema.file

      collection = build_managed_concept_collection(schema)
      output_data(collection)
      collection
    end

    def output_data(collection)
      FileUtils.mkdir_p(File.expand_path(@output_path)) unless File.exist?(@output_path)
      Utils.log "Saving collection to files in: #{@output_path}"
      collection.save_to_files(File.expand_path(@output_path))
    end

    def build_managed_concept_collection(schema)
      source_ref = get_source_ref(schema)

      Glossarist::ManagedConceptCollection.new.tap do |collection|
        schema.entities.each do |entity|
          localized_concept = build_localized_concept(
            schema: schema,
            entity: entity,
            source_ref: source_ref,
          )
          localized_concept_id = get_localized_concept_identifier(schema, entity)

          managed_data = Glossarist::ManagedConceptData.new.tap do |data|
            data.id = get_entity_identifier(schema, entity)
            data.localizations[@language_code] = localized_concept
            data.localized_concepts = { @language_code => localized_concept_id }
          end

          managed_concept = Glossarist::ManagedConcept.new.tap do |concept|
            concept.id = get_entity_identifier(schema, entity)
            concept.uuid = concept.id
            concept.data = managed_data
          end

          collection.store(managed_concept)
        end
      end
    end

    def build_localized_concept(schema:, entity:, source_ref:)
      schema_domain = get_domain(schema)

      localized_concept_data = Glossarist::ConceptData.new.tap do |data|
        data.terms = get_entity_terms(entity)
        data.definition = get_entity_definitions(entity, schema)
        data.language_code = @language_code
        data.domain = schema_domain
        data.sources = [source_ref] if source_ref

        notes = get_entity_notes(entity, schema_domain, data.definition)
        data.notes = notes if notes && !notes.empty?
        data.examples = []
      end

      Glossarist::LocalizedConcept.new.tap { |c| c.data = localized_concept_data }
    end

    def get_entity_identifier(schema, entity)
      "#{schema.id}.#{entity.id}"
    end

    def get_localized_concept_identifier(schema, entity)
      "#{schema.id}.#{entity.id}-#{@language_code}"
    end

    def get_source_ref(schema)
      origin = Glossarist::Citation.new.tap do |citation|
        citation.ref = "ISO 10303"
        custom_locality = build_custom_locality(schema)
        citation.custom_locality = custom_locality unless custom_locality.empty?
      end

      Glossarist::ConceptSource.new(type: "authoritative", origin: origin)
    end

    def build_custom_locality(schema)
      localities = []
      localities << Glossarist::CustomLocality.new(name: "schema", value: schema.id)

      version_item = schema.version.items.detect { |i| i.name == "version" }
      if version_item
        localities << Glossarist::CustomLocality.new(name: "version", value: version_item.value)
      end

      localities
    end

    def get_domain(schema)
      prefix = if schema.id.end_with?("_arm", "_mim")
                 "application module"
               else
                 "resource"
               end

      "#{prefix}: #{schema.id}"
    end

    def get_entity_terms(entity)
      [
        Glossarist::Designation::Base.new(
          designation: entity.id,
          type: "expression",
          normative_status: "preferred",
        ),
      ]
    end

    def get_entity_definitions(entity, schema)
      schema_type = extract_file_type(schema.file)
      schema_domain = get_domain(schema)

      definition = generate_entity_definition(entity, schema_domain, schema_type)
      [Glossarist::DetailedDefinition.new(content: definition)]
    end

    def get_entity_notes(entity, schema_domain, definitions)
      notes = []

      if entity.remarks && !entity.remarks.empty?
        trimmed_def = trim_definition(entity.remarks)
        if trimmed_def && !trimmed_def.empty?
          notes << Glossarist::DetailedDefinition.new(
            content: convert_express_xref(trimmed_def, schema_domain),
          )
        end
      end

      notes = only_keep_first_sentence(notes)
      notes = remove_see_content(notes)
      notes = remove_redundant_note(notes)
      notes = remove_invalid_references(notes)
      compare_with_definitions(notes, definitions)
    end

    def only_keep_first_sentence(notes)
      notes.each do |note|
        if note&.content && should_preserve_complete_structure?(note.content)
          next
        end

        if note&.content
          new_content = note.content
            .split(".\n").first.strip
            .split(". ").first.strip
          note.content = new_content.end_with?(".") ? new_content : "#{new_content}."
        end
      end
    end

    def should_preserve_complete_structure?(content)
      return false if content.nil? || content.empty?

      lines = content.split("\n")
      first_paragraph = lines.first&.strip

      if first_paragraph&.end_with?(":") && lines.length > 1
        if first_paragraph.count(".").positive?
          return false
        end

        remaining_content = lines[1..].join("\n")
        return starts_with_list?(remaining_content.strip)
      end

      false
    end

    def compare_with_definitions(notes, definitions)
      if notes&.first&.content == definitions&.first&.content
        return []
      end

      notes
    end

    def remove_invalid_references(notes)
      notes.reject do |note|
        note.content.include?("image::") ||
          note.content.match?(/<<(.*?){1,999}>>/)
      end
    end

    def remove_redundant_note(notes)
      notes.reject do |note|
        note.content.match?(REDUNDANT_NOTE_REGEX) &&
          !note.content.include?("\n")
      end
    end

    def remove_see_content(notes)
      notes.each do |note|
        note.content = note.content.gsub(/\s+\(see(.*?){1,999}\)/, "")
      end
    end

    def extract_file_type(filename)
      match = filename.match(/(arm|mim|bom)_annotated\.exp$/)
      return "resource" unless match

      {
        "arm" => "module_arm",
        "mim" => "module_mim",
        "bom" => "business_object_model",
      }[match.captures[0]] || "resource"
    end

    def starts_with_list?(content)
      return false if content.nil? || content.empty?

      content.match?(/^\s*[\*\-\+]\s+/) || content.match?(/^\s*\d+\.\s+/)
    end

    def trim_definition(definition)
      return nil if definition.nil? || definition.empty?

      definition_str = definition.is_a?(Array) ? definition.join("\n\n") : definition.to_s

      return nil if definition_str.empty?

      paragraphs = definition_str.split("\n\n")
      first_paragraph = paragraphs.first

      combined = if paragraphs.length == 1
                   apply_first_sentence_logic(first_paragraph)
                 elsif first_paragraph.end_with?(":") && paragraphs.length > 1 && starts_with_list?(paragraphs[1])
                   complete_list = extract_complete_list(paragraphs, 1)
                   "#{first_paragraph}\n\n#{complete_list}"
                 else
                   apply_first_sentence_logic(first_paragraph)
                 end

      combined = "#{combined}\n"
      combined.gsub!(/\n\/\/.*?\n/, "\n")
      combined.strip!

      express_reference_to_mention(combined)
    end

    def apply_first_sentence_logic(paragraph)
      new_content = paragraph
        .split(".\n").first.strip
        .split(". ").first.strip

      new_content.end_with?(".") ? new_content : "#{new_content}."
    end

    def extract_complete_list(paragraphs, start_index)
      return paragraphs[start_index] if start_index >= paragraphs.length

      combined = paragraphs[start_index].dup
      current_index = start_index + 1
      in_continuation_block = combined.include?("--") && !combined.match?(/--.*--/m)

      while current_index < paragraphs.length
        next_para = paragraphs[current_index]

        if next_para.match?(/^--\s*$/) || next_para.end_with?("--")
          in_continuation_block = !in_continuation_block
          combined += "\n\n#{next_para}"
          current_index += 1
          next
        end

        if in_continuation_block
          combined += "\n\n#{next_para}"
          current_index += 1
          next
        end

        if starts_with_list?(next_para) || is_list_continuation?(next_para)
          combined += "\n\n#{next_para}"
          current_index += 1
          in_continuation_block = true if next_para.include?("--") && !next_para.match?(/--.*--/m)
        else
          break
        end
      end

      combined
    end

    def is_list_continuation?(content)
      return false if content.nil? || content.empty?

      content.match?(/^\+\s*$/) ||
        content.match?(/^--\s*$/) ||
        content.match?(/^\s{2,}/) ||
        content.start_with?("which", "where", "that")
    end

    def express_reference_to_mention(description)
      description
        .gsub(/<<express:([^,]+)>>/) do |_match|
          "{{#{Regexp.last_match[1].split('.').last}}}"
        end.gsub(/<<express:([^,]+),([^>]+)>>/) do |_match|
          "{{#{Regexp.last_match[1].split('.').last}," \
            "#{Regexp.last_match[2]}}}"
        end
    end

    def entity_name_to_text(entity_id)
      entity_id.downcase.gsub("_", " ")
    end

    def generate_entity_definition(entity, _domain, schema_type)
      return "" if entity.nil?

      entity_type = case schema_type
                    when "module_arm"
                      "{{application object}}"
                    when "module_mim"
                      "{{entity data type}}"
                    when "resource", "business_object_model"
                      "{{entity data type}}"
                    else
                      raise Error, "[suma] encountered unsupported schema_type"
                    end

      if entity.subtype_of.empty?
        "#{entity_type} " \
          "that represents the " \
          "#{entity_name_to_text(entity.id)} {{entity}}"
      else
        entity_subtypes = entity.subtype_of.map { |e| "{{#{e.id}}}" }

        "#{entity_type} that is a type of " \
          "#{entity_subtypes.join(' and ')} " \
          "that represents the " \
          "#{entity_name_to_text(entity.id)} {{entity}}"
      end
    end

    def convert_express_xref(content, schema_domain)
      content.gsub(/<<express:(.*),(.*)>>/) do
        "{{<#{schema_domain}>" \
          "#{Regexp.last_match(1).split('.').last},#{Regexp.last_match(2)}}}"
      end
    end
  end
end
