# frozen_string_literal: true

require "thor"
require_relative "../thor_ext"
require "fileutils"
require "expressir"
require "securerandom"
require "glossarist"

module Suma
  module Cli
    # ExtractTerms command using Expressir to extract terms into the
    # Glossarist v2 format
    class ExtractTerms < Thor
      # Matches patterns like "A thing is a type of {{entity}}." or
      # "An object is a type of a {{entity}}"
      REDUNDANT_NOTE_REGEX =
        %r{
          ^An?                   # Starts with "A" or "An"
          \s.*?\sis\sa\stype\sof # Text followed by "is a type of"
          (\sa|\san)?            # Optional " a" or " an"
          \s\{\{[^\}]*\}\}       # Text in double curly braces
          \s*?\.?$               # Optional whitespace and period at the end
        }x

      desc "extract_terms SCHEMA_MANIFEST_FILE GLOSSARIST_OUTPUT_PATH",
           "Extract terms from SCHEMA_MANIFEST_FILE into " \
           "Glossarist v2 format"
      option :language_code, type: :string, default: "eng", aliases: "-l",
                             desc: "Language code for the Glossarist"

      def extract_terms(schema_manifest_file, output_path)
        language_code = options[:language_code]
        schema_manifest_file = File.expand_path(schema_manifest_file)

        unless File.exist?(schema_manifest_file)
          raise Errno::ENOENT, "Specified SCHEMA_MANIFEST_FILE " \
                               "`#{schema_manifest_file}` not found."
        end

        run(schema_manifest_file, output_path, language_code)
      end

      private

      def run(schema_manifest_file, output_path, language_code = "eng")
        get_exp_files(schema_manifest_file).map do |exp_file|
          extract(exp_file, output_path, language_code)
        end
      end

      def get_exp_files(schema_manifest_file)
        config = Expressir::SchemaManifest.from_file(schema_manifest_file)
        paths = config.schemas.map(&:path)

        if paths.empty?
          raise Errno::ENOENT, "No EXPRESS files found in " \
                               "`#{schema_manifest_file}`."
        end

        paths
      end

      def extract(exp_file, output_path, language_code)
        exp_path_rel = Pathname.new(exp_file).relative_path_from(Pathname.getwd)
        puts "Building terms: #{exp_path_rel}"

        repo = Expressir::Express::Parser.from_file(exp_file)
        schema = get_default_schema(repo)

        unless schema.file
          raise Error.new("Schema must have an associated file")
        end

        collection = build_managed_concept_collection(
          schema, language_code
        )

        output_data(collection, output_path)
      end

      def output_data(collection, output_path)
        unless File.exist?(output_path)
          FileUtils.mkdir_p(File.expand_path(output_path))
        end

        puts "Saving collection to files in: #{output_path}"
        collection.save_to_files(File.expand_path(output_path))

        collection
      end

      def build_managed_concept_collection(schema, language_code)
        Glossarist::ManagedConceptCollection.new.tap do |collection|
          # Extract schema-level citation data once to reuse across all entities
          source_ref = get_source_ref(schema)

          # Create one concept per entity
          schema.entities.each do |entity|
            localized_concept = build_localized_concept(
              schema: schema,
              entity: entity,
              language_code: language_code,
              source_ref: source_ref,
            )
            localized_concept_id = get_localized_concept_identifier(
              schema, entity, language_code
            )
            localized_concept.uuid = localized_concept_id

            managed_data = Glossarist::ManagedConceptData.new.tap do |data|
              data.id = get_entity_identifier(schema, entity)

              # TODO: Why do we need both localizations and localized_concepts??
              data.localizations[language_code] = localized_concept
              # uuid is automatically set from the serialization of the object
              data.localized_concepts = {
                language_code => localized_concept_id,
              }
            end

            managed_concept = Glossarist::ManagedConcept.new.tap do |concept|
              # uuid is automatically set from the serialization of the object
              concept.id = get_entity_identifier(schema, entity)
              concept.uuid = concept.id
              concept.data = managed_data
            end

            collection.store(managed_concept)
          end
        end
      end

      def build_localized_concept(schema:, entity:, language_code:, source_ref:)
        schema_domain = get_domain(schema)

        localized_concept_data = Glossarist::ConceptData.new.tap do |data|
          data.terms = get_entity_terms(entity)
          data.definition = get_entity_definitions(entity, schema)
          data.language_code = language_code
          data.domain = schema_domain
          data.sources = [source_ref] if source_ref

          # Only assign optional fields if they have content
          notes = get_entity_notes(entity, schema_domain, data.definition)
          data.notes = notes if notes && !notes.empty?

          # examples = get_entity_examples(entity, schema_domain)
          # data.examples = examples if examples && !examples.empty?
          data.examples = []
        end

        Glossarist::LocalizedConcept.new.tap do |concept|
          concept.data = localized_concept_data
        end
      end

      # We only deal with 1 schema
      def get_default_schema(repo)
        repo.schemas.first
      end

      def find_remark_value(schema, remark_id)
        schema.remark_items.find { |s| s.id == remark_id }&.remarks&.first
      end

      def get_entity_identifier(schema, entity)
        "#{schema.id}.#{entity.id}"
      end

      def get_localized_concept_identifier(schema, entity, lang)
        "#{schema.id}.#{entity.id}-#{lang}"
      end

      def get_source_ref(schema)
        origin = Glossarist::Citation.new.tap do |citation|
          citation.ref = "ISO 10303"
          custom_locality = build_custom_locality(schema)

          unless custom_locality.empty?
            citation.custom_locality = custom_locality
          end
        end

        Glossarist::ConceptSource.new(type: "authoritative", origin: origin)
      end

      # SCHEMA action_schema
      # '{iso standard 10303 part(41) version(9) object(1) action-schema(1)}';
      def build_custom_locality(schema)
        [].tap do |localities|
          # Add schema name
          localities << Glossarist::CustomLocality.new(
            name: "schema",
            value: schema.id,
          )

          # Add version if available
          version_item = schema.version.items.detect { |i| i.name == "version" }
          if version_item
            localities << Glossarist::CustomLocality.new(
              name: "version",
              value: version_item.value,
            )
          end
        end
      end

      # TODO: What if this was a "bom"?
      def get_domain(schema)
        prefix = if mim?(schema.id) || arm?(schema.id)
                   "application module"
                 else
                   "resource"
                 end

        "#{prefix}: #{schema.id}"
      end

      def arm?(schema_id)
        schema_id.end_with?("_arm")
      end

      def mim?(schema_id)
        schema_id.end_with?("_mim")
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

      def get_entity_terms(entity)
        # For now, use the entity ID as the term
        # This could be enhanced to look for entity-specific title remark items
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

        definition = generate_entity_definition(entity, schema_domain,
                                                schema_type)
        [Glossarist::DetailedDefinition.new(content: definition)]
      end

      def get_entity_notes(entity, schema_domain, definitions)
        puts "Extracting notes for entity: #{entity.id}"
        notes = []

        notes = add_entity_notes(entity, schema_domain, notes)
        # notes = add_other_notes(entity, schema_domain, notes)
        notes = only_keep_first_sentence(notes)
        notes = remove_see_content(notes)
        notes = remove_redundant_note(notes)
        notes = remove_invalid_references(notes)
        compare_with_definitions(notes, definitions)
      end

      def add_entity_notes(entity, schema_domain, notes)
        # Add trimmed definition from entity description as first note
        if entity.remarks && !entity.remarks.empty?
          trimmed_def = trim_definition(entity.remarks)
          if trimmed_def && !trimmed_def.empty?
            notes << Glossarist::DetailedDefinition.new(
              content: convert_express_xref(trimmed_def, schema_domain),
            )
          end
        end

        notes.compact
      end

      def add_other_notes(entity, schema_domain, notes)
        # Add other notes from entity remarks
        other_notes = [
          entity.remark_items&.select do |ri|
            ri.id == "__note"
          end&.map(&:remarks),
        ].flatten.compact

        other_notes.each do |note|
          notes << Glossarist::DetailedDefinition.new(
            content: convert_express_xref(note, schema_domain),
          )
        end

        notes
      end

      # https://github.com/metanorma/iso-10303/issues/621
      # 1. First sentence in first paragraph of the entity description
      # (in EXPRESS remark) becomes NOTE 1 in ISO 10303-2 of the entity.
      def only_keep_first_sentence(notes)
        notes.each do |note|
          # Skip truncation only for content that starts with a paragraph ending in ":"
          # followed by a list (complete list structures that should be preserved)
          if note&.content && should_preserve_complete_structure?(note.content)
            # For complete list structures, keep the content as-is
            next
          end

          # Split by period and take the first sentence for all other content
          # Avoid splitting by pattern like "abc.def"
          if note&.content
            new_content = note.content
              .split(".\n").first.strip
              .split(". ").first.strip
            note.content = if new_content.end_with?(".")
                             new_content
                           else
                             "#{new_content}."
                           end
          end
        end
      end

      def should_preserve_complete_structure?(content)
        return false if content.nil? || content.empty?

        # Check if content starts with a single introductory sentence ending in ":"
        # followed by a list. This indicates a complete list structure that should be preserved.
        lines = content.split("\n")
        first_paragraph = lines.first&.strip

        # Look for pattern: Single sentence ending with ":" (introductory pattern)
        if first_paragraph&.end_with?(":") && lines.length > 1
          # Check if the first paragraph contains multiple sentences (periods before the colon)
          # If it does, this is NOT an introductory paragraph - extract first sentence only
          if first_paragraph.count(".").positive?
            return false
          end

          # Check if there's a list after the colon
          remaining_content = lines[1..].join("\n")
          return starts_with_list?(remaining_content.strip)
        end

        false
      end

      # https://github.com/metanorma/iso-10303/issues/621
      # 2. If this first sentence matches the 7-word magic sentence
      # (2-3 forms of that), it is discarded so there will not be a NOTE 1.
      def compare_with_definitions(notes, definitions)
        if notes&.first&.content == definitions&.first&.content
          # Discarding first note as it matches the definition
          return []
        end

        notes
      end

      # https://github.com/metanorma/iso-10303/issues/621
      # 3. No reference to any types or attribute or figures allowed in first
      # sentence. Entity references “{{…}}” are allowed.
      def remove_invalid_references(notes)
        notes.reject do |note|
          note.content.include?("image::") ||
            note.content.match?(/<<(.*?){1,999}>>/)
        end
      end

      # https://github.com/metanorma/iso-10303/issues/621
      # 4. Entity notes and examples in EXPRESS remarks are NOT represented in
      # part 2.
      def remove_redundant_note(notes)
        notes.reject do |note|
          note.content.match?(REDUNDANT_NOTE_REGEX) &&
            !note.content.include?("\n")
        end
      end

      # https://github.com/metanorma/iso-10303/issues/621
      # 5. If the sentence contains “\s+(see …)”, the contents including the
      # parentheses are removed.
      def remove_see_content(notes)
        notes.each do |note|
          note.content = note.content.gsub(/\s+\(see(.*?){1,999}\)/, "")
        end
      end

      def get_entity_examples(entity, schema_domain)
        examples = entity.remark_items&.select do |ri|
          ri.id == "__example"
        end&.map(&:remarks)&.flatten&.compact || []

        examples.map do |example|
          Glossarist::DetailedDefinition.new(
            content: convert_express_xref(example, schema_domain),
          )
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

      def get_schema_type(schema)
        return "mim" if mim?(schema.id)
        return "arm" if arm?(schema.id)
        return "bom" if bom?(schema.id)

        "resource"
      end

      def bom?(schema_id)
        schema_id.end_with?("_bom")
      end

      def contains_list?(content)
        return false if content.nil? || content.empty?

        # Check if content contains list markers
        content.match?(/^\s*[\*\-\+]\s+/m) || content.match?(/^\s*\d+\.\s+/m)
      end

      def starts_with_list?(content)
        return false if content.nil? || content.empty?

        # Check if content starts with list markers
        content.match?(/^\s*[\*\-\+]\s+/) || content.match?(/^\s*\d+\.\s+/)
      end

      def is_list_continuation?(content)
        return false if content.nil? || content.empty?

        # Check for AsciiDoc list continuation patterns
        content.match?(/^\+\s*$/) ||
          content.match?(/^--\s*$/) ||
          content.match?(/^\s{2,}/) || # Indented content (continuation)
          content.start_with?("which", "where", "that") # Logical continuation
      end

      def extract_complete_list(paragraphs, start_index)
        return paragraphs[start_index] if start_index >= paragraphs.length

        combined = paragraphs[start_index].dup
        current_index = start_index + 1

        # Check if the first paragraph already contains an opening continuation block
        in_continuation_block = combined.include?("--") && !combined.match?(/--.*--/m)

        # Continue collecting paragraphs while we're in a list context
        while current_index < paragraphs.length
          next_para = paragraphs[current_index]

          # Check if we're entering or exiting a continuation block
          if next_para.match?(/^--\s*$/) || next_para.end_with?("--")
            in_continuation_block = !in_continuation_block
            combined += "\n\n#{next_para}"
            current_index += 1
            next
          end

          # If we're in a continuation block, include all content until we hit the closing --
          if in_continuation_block
            combined += "\n\n#{next_para}"
            current_index += 1
            next
          end

          # Check if this is a list item or list continuation
          if starts_with_list?(next_para) || is_list_continuation?(next_para)
            combined += "\n\n#{next_para}"
            current_index += 1

            # Check if this paragraph contains an opening continuation block
            if next_para.include?("--") && !next_para.match?(/--.*--/m)
              in_continuation_block = true
            end
          else
            # This paragraph is not part of the list structure
            break
          end
        end

        combined
      end

      def ends_list_structure?(current_para, next_para)
        return true if next_para.nil?

        # List ends if:
        # 1. Current paragraph doesn't end with continuation markers
        # 2. Next paragraph starts a new section (not list or continuation)
        !current_para.match?(/\+\s*$/) &&
          !starts_with_list?(next_para) &&
          !is_list_continuation?(next_para)
      end

      def apply_first_sentence_logic(paragraph)
        # Apply the original first-sentence extraction logic
        # Split by period and take the first sentence
        # Avoid splitting by pattern like "abc.def"
        new_content = paragraph
          .split(".\n").first.strip
          .split(". ").first.strip

        if new_content.end_with?(".")
          new_content
        else
          "#{new_content}."
        end
      end

      # rubocop:disable Metrics/MethodLength
      def combine_paragraphs(full_paragraph, next_paragraph)
        # Check if we're dealing with a list structure
        if contains_list?(full_paragraph) || starts_with_list?(next_paragraph)
          return combine_list_content(full_paragraph, next_paragraph)
        end

        # For regular paragraphs, apply the original first-sentence logic
        # If full_paragraph already contains a period, extract that.
        if m = full_paragraph.match(/\A(?<inner_first>[^\n]*?\.)\s/)
          if m[:inner_first]
            return m[:inner_first]
          else
            return full_paragraph
          end
        end

        # If full_paragraph ends with a period, this is the last.
        if /\.\s*\Z/.match?(full_paragraph)
          return full_paragraph
        end

        # If next_paragraph is a continuation of a paragraph
        if next_paragraph&.start_with?("which", "where", "that")
          return "#{full_paragraph}\n\n#{next_paragraph}"
        end

        full_paragraph
      end

      def combine_list_content(full_paragraph, next_paragraph)
        combined = full_paragraph.dup

        # If we have a next paragraph, add it
        unless next_paragraph.nil? || next_paragraph.empty?
          combined += "\n\n#{next_paragraph}"
        end

        combined
      end

      def trim_definition(definition)
        return nil if definition.nil? || definition.empty?

        # Handle case where definition is an array
        definition_str = if definition.is_a?(Array)
                           definition.join("\n\n")
                         else
                           definition.to_s
                         end

        return nil if definition_str.empty?

        paragraphs = definition_str.split("\n\n")
        first_paragraph = paragraphs.first

        # If we only have one paragraph, apply the original logic
        if paragraphs.length == 1
          combined = apply_first_sentence_logic(first_paragraph)
        elsif first_paragraph.end_with?(":") && paragraphs.length > 1 && starts_with_list?(paragraphs[1])
          # Case 1: First paragraph ends with ":" and leads into a list
          # Extract the complete list structure (this is an introductory paragraph)
          complete_list = extract_complete_list(paragraphs, 1)
          combined = "#{first_paragraph}\n\n#{complete_list}"
        else
          # Case 2: For all other cases (including sentences followed by lists)
          # Extract only the first sentence from the first paragraph
          combined = apply_first_sentence_logic(first_paragraph)
        end

        # Remove comments until end of line
        combined = "#{combined}\n"
        combined.gsub!(/\n\/\/.*?\n/, "\n")
        combined.strip!

        express_reference_to_mention(combined)
      end
      # rubocop:enable Metrics/MethodLength

      # Replace `<<express:{schema}.{entity}>>` with {{entity}}
      # and `<<express:{schema}.{entity},{render}>>` with {{entity,render}}
      def express_reference_to_mention(description)
        # TODO: Use Expressir to check whether the "entity" is really an
        # EXPRESS ENTITY. If not, skip the mention.
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

      # rubocop:disable Layout/LineLength
      def generate_entity_definition(entity, _domain, schema_type)
        return "" if entity.nil?

        # See: metanorma/iso-10303-2#90
        entity_type = case schema_type
                      when "module_arm"
                        "{{application object}}"
                      when "module_mim"
                        "{{entity data type}}"
                      when "resource", "business_object_model"
                        "{{entity data type}}"
                      else
                        raise Error.new("[suma] encountered unsupported schema_type")
                      end

        if entity.subtype_of.empty?
          "#{entity_type} " \
            "that represents the " \
            "#{entity_name_to_text(entity.id)} {{entity}}"
        else
          entity_subtypes = entity.subtype_of.map do |e|
            "{{#{e.id}}}"
          end

          "#{entity_type} that is a type of " \
            "#{entity_subtypes.join(' and ')} " \
            "that represents the " \
            "#{entity_name_to_text(entity.id)} {{entity}}"
        end
      end
      # rubocop:enable Layout/LineLength

      def convert_express_xref(content, schema_domain)
        content.gsub(/<<express:(.*),(.*)>>/) do
          "{{<#{schema_domain}>" \
            "#{Regexp.last_match(1).split('.').last},#{Regexp.last_match(2)}}}"
        end
      end

      def id_from_designation(designation)
        designation.gsub(" ", "_").gsub("/", "_").gsub(":", "_")
      end
    end
  end
end
