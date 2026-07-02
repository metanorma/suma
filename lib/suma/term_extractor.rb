# frozen_string_literal: true

require "fileutils"
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

    def initialize(schema_manifest_file, output_path, urn:,
                   language_code: "eng")
      @schema_manifest_file = File.expand_path(schema_manifest_file)
      @output_path = output_path
      @language_code = language_code
      @urn = Suma::Urn.new(urn)
    end

    def call
      validate_inputs
      get_exp_files.map do |exp_file|
        extract(exp_file)
      end
    end

    private

    def validate_inputs
      unless File.exist?(@schema_manifest_file)
        raise Errno::ENOENT, "Specified SCHEMA_MANIFEST_FILE " \
                             "`#{@schema_manifest_file}` not found."
      end
      unless File.file?(@schema_manifest_file)
        raise Errno::ENOENT, "Specified SCHEMA_MANIFEST_FILE " \
                             "`#{@schema_manifest_file}` is not a file."
      end
    end

    def get_exp_files
      config = Expressir::SchemaManifest.from_file(@schema_manifest_file)
      paths = config.schemas.map(&:path)

      if paths.empty?
        raise Errno::ENOENT,
              "No EXPRESS files found in `#{@schema_manifest_file}`."
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
      output_dir = File.expand_path(@output_path)
      FileUtils.mkdir_p(output_dir)
      Utils.log "Saving collection to files in: #{@output_path}"

      collection.each do |concept|
        doc = Glossarist::V3::ConceptDocument.from_managed_concept(concept)
        doc.localizations = concept.data.localizations.keys.map do |lang|
          concept.localization(lang)
        end

        filename = "#{concept.uuid.gsub(/[^\w.-]/, '_')}.yaml"
        File.write(File.join(output_dir, filename), doc.to_yamls,
                   encoding: "utf-8")
      end
    end

    def build_managed_concept_collection(schema)
      source_ref = get_source_ref(schema)
      section_ref = get_section_ref(schema)

      Glossarist::ManagedConceptCollection.new.tap do |collection|
        schema.entities.each do |entity|
          localized_concept_id = Glossarist::Utilities::UUID.uuid_v5(
            Glossarist::Utilities::UUID::OID_NAMESPACE,
            "#{schema.id}.#{entity.id}-#{@language_code}",
          )

          localized_concept = build_localized_concept(
            schema: schema,
            entity: entity,
            source_ref: source_ref,
            uuid: localized_concept_id,
          )

          managed_data = Glossarist::V3::ManagedConceptData.new.tap do |data|
            data.id = "#{schema.id}.#{entity.id}"
            data.localizations.store(@language_code, localized_concept)
            data.localized_concepts = { @language_code => localized_concept_id }
            data.domains = [section_ref] if section_ref
          end

          managed_concept = Glossarist::V3::ManagedConcept.new.tap do |concept|
            concept.id = managed_data.id
            concept.uuid = Glossarist::Utilities::UUID.uuid_v5(
              Glossarist::Utilities::UUID::OID_NAMESPACE,
              managed_data.id,
            )
            concept.data = managed_data
            concept.schema_version = "v3"
          end

          collection.store(managed_concept)
        end
      end
    end

    def build_localized_concept(schema:, entity:, source_ref:, uuid:)
      schema_domain = get_domain(schema)

      localized_concept_data = Glossarist::V3::ConceptData.new.tap do |data|
        data.terms = get_entity_terms(entity)
        data.definition = get_entity_definitions(entity, schema)
        data.language_code = @language_code
        data.domain = schema_domain
        data.sources = [source_ref] if source_ref

        notes = get_entity_notes(entity, schema_domain, data.definition)
        data.notes = notes if notes && !notes.empty?
        data.examples = []
      end

      Glossarist::V3::LocalizedConcept.new(
        data: localized_concept_data, uuid: uuid,
      )
    end

    def schema_urn(schema)
      @urn.for_schema(schema.id)
    end

    def term_urn(concept_identifier)
      @urn.for_term(concept_identifier)
    end

    def express_entity_urn(full_ref)
      @urn.for_entity(full_ref)
    end

    def urn_mention(urn, display)
      "{{#{urn},#{display}}}"
    end

    def get_section_ref(schema)
      return nil unless @urn

      Glossarist::ConceptReference.new(
        concept_id: "section-#{schema.id}",
        source: schema_urn(schema),
        ref_type: "section",
      )
    end

    def get_source_ref(schema)
      ref = Glossarist::Citation::Ref.new
      ref.source = schema_urn(schema)

      build_custom_locality(schema).each do |cl|
        case cl.name
        when "version" then ref.version = cl.value
        end
      end

      origin = Glossarist::V3::Citation.new
      origin.ref = ref
      Glossarist::V3::ConceptSource.new(id: schema.id, type: "authoritative",
                                        origin: origin)
    end

    def build_custom_locality(schema)
      localities = []

      version_item = schema.version.items.detect { |i| i.name == "version" }
      if version_item
        localities << Glossarist::CustomLocality.new(name: "version",
                                                     value: version_item.value)
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
      get_domain(schema)

      definition = generate_entity_definition(entity, schema, schema_type)
      [Glossarist::V3::DetailedDefinition.new(content: definition)]
    end

    def get_entity_notes(entity, schema_domain, definitions)
      notes = []

      if entity.remarks && !entity.remarks.empty?
        trimmed_def = trim_definition(entity.remarks)
        if trimmed_def && !trimmed_def.empty?
          notes << Glossarist::V3::DetailedDefinition.new(
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

      content.match?(/^\s*[*\-+]\s+/) || content.match?(/^\s*\d+\.\s+/)
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
        .gsub(/<<express:([\w.]+)>>/) do |_match|
          full_ref = Regexp.last_match[1]
          entity_id = full_ref.split(".").last
          urn_mention(express_entity_urn(full_ref), entity_id)
        end.gsub(/<<express:([\w.]+),([\w. ][\w. ]*)>>/) do |_match|
          full_ref = Regexp.last_match[1]
          display = Regexp.last_match(2)
          urn_mention(express_entity_urn(full_ref), display)
        end
    end

    def entity_name_to_text(entity_id)
      entity_id.downcase.gsub("_", " ")
    end

    def generate_entity_definition(entity, schema, schema_type)
      return "" if entity.nil?

      entity_type = case schema_type
                    when "module_arm"
                      urn_mention(term_urn("general.application_object"),
                                  "application object")
                    when "module_mim"
                      urn_mention(term_urn("express-language.entity_data_type"),
                                  "entity data type")
                    when "resource", "business_object_model"
                      urn_mention(term_urn("express-language.entity_data_type"),
                                  "entity data type")
                    else
                      raise Error, "[suma] encountered unsupported schema_type"
                    end

      entity_ref = urn_mention(term_urn("express-language.entity"), "entity")

      if entity.subtype_of.empty?
        "#{entity_type} " \
          "that represents the " \
          "#{entity_name_to_text(entity.id)} #{entity_ref}"
      else
        entity_subtypes = entity.subtype_of.map do |e|
          urn_mention(express_entity_urn("#{schema.id}.#{e.id}"), e.id)
        end

        "#{entity_type} that is a type of " \
          "#{entity_subtypes.join(' and ')} " \
          "that represents the " \
          "#{entity_name_to_text(entity.id)} #{entity_ref}"
      end
    end

    def convert_express_xref(content, _schema_domain)
      content.gsub(/<<express:([\w.]+),([\w. ][\w. ]*)>>/) do
        full_ref = Regexp.last_match(1)
        display = Regexp.last_match(2)
        urn_mention(express_entity_urn(full_ref), display)
      end
    end
  end
end
