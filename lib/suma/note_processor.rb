# frozen_string_literal: true

require "glossarist"

module Suma
  # Cleans raw EXPRESS entity remarks into a list of
  # +Glossarist::V3::DetailedDefinition+ notes.
  #
  # Pipeline:
  #   1. trim to first sentence / first complete list
  #   2. convert express xrefs to URN mentions
  #   3. drop redundant "X is a type of {{...}}" opening notes
  #   4. drop notes containing image references or <<...>> blocks
  #   5. drop notes that duplicate the first definition
  #
  # Pure: no I/O, no schema knowledge. The schema domain label and
  # URN composition are injected via +xref_to_mention+ so this module
  # stays independent of +Suma::Urn+ and the surrounding extractor.
  class NoteProcessor
    REDUNDANT_NOTE_REGEX =
      %r{
        ^An?                   # Starts with "A" or "An"
        \s.*?\sis\sa\stype\sof # Text followed by "is a type of"
        (\sa|\san)?            # Optional " a" or " an"
        \s\{\{[^\}]*\}\}       # Text in double curly braces
        \s*?\.?$               # Optional whitespace and period at the end
      }x

    IMAGE_REF_SUBSTRING = "image::"
    DOUBLE_ANGLE_PATTERN = /<<(.*?){1,999}>>/
    SEE_TAIL_PATTERN = /\s+\(see(.*?){1,999}\)/
    XREF_WITH_DISPLAY = /<<express:([\w.]+),([\w. ][\w. ]*)>>/
    XREF_WITHOUT_DISPLAY = /<<express:([\w.]+)>>/
    INLINE_COMMENT_PATTERN = /\n\/\/.*?\n/
    BULLET_LIST_PATTERN = /^\s*[*\-+]\s+/
    NUMBERED_LIST_PATTERN = /^\s*\d+\.\s+/
    CONTINUATION_PLUS = /^\+\s*$/
    CONTINUATION_DASHES = /^--\s*$/
    INDENTED_PATTERN = /^\s{2,}/
    SENTENCE_BREAK_NEWLINE = /\.\n/
    SENTENCE_BREAK_SPACE = /\. /

    attr_reader :remarks, :definitions, :xref_to_mention

    def initialize(remarks, definitions:, xref_to_mention:)
      @remarks = remarks
      @definitions = definitions
      @xref_to_mention = xref_to_mention
    end

    def self.call(remarks, definitions:, xref_to_mention:)
      new(remarks, definitions: definitions, xref_to_mention: xref_to_mention).call
    end

    def call
      notes = build_initial_notes
      notes = only_keep_first_sentence(notes)
      notes = remove_see_content(notes)
      notes = remove_redundant_note(notes)
      notes = remove_invalid_references(notes)
      compare_with_definitions(notes, definitions)
    end

    private

    def build_initial_notes
      trimmed = trim_definition(remarks)
      return [] unless trimmed && !trimmed.empty?

      [Glossarist::V3::DetailedDefinition.new(content: trimmed)]
    end

    def trim_definition(definition)
      return nil if definition.nil? || definition.empty?

      definition_str = array_to_paragraphs(definition)
      return nil if definition_str.empty?

      paragraphs = definition_str.split("\n\n")
      combine_paragraphs(paragraphs)
    end

    def array_to_paragraphs(definition)
      definition.is_a?(Array) ? definition.join("\n\n") : definition.to_s
    end

    def combine_paragraphs(paragraphs)
      combined = first_block(paragraphs)
      combined = "#{combined}\n"
      combined = combined.gsub(INLINE_COMMENT_PATTERN, "\n")
      combined.strip!
      convert_xref(combined)
    end

    def first_block(paragraphs)
      first_paragraph = paragraphs.first
      return apply_first_sentence_logic(first_paragraph) unless list_header?(paragraphs)

      complete_list = extract_complete_list(paragraphs, 1)
      "#{first_paragraph}\n\n#{complete_list}"
    end

    def list_header?(paragraphs)
      paragraphs.length > 1 &&
        paragraphs.first.end_with?(":") &&
        starts_with_list?(paragraphs[1])
    end

    def apply_first_sentence_logic(paragraph)
      new_content = paragraph
        .split(SENTENCE_BREAK_NEWLINE).first.strip
        .split(SENTENCE_BREAK_SPACE).first.strip

      new_content.end_with?(".") ? new_content : "#{new_content}."
    end

    def extract_complete_list(paragraphs, start_index)
      return paragraphs[start_index] if start_index >= paragraphs.length

      reduce_list_paragraphs(paragraphs, start_index)
    end

    def reduce_list_paragraphs(paragraphs, start_index)
      combined = paragraphs[start_index].dup
      state = ContinuationState.new(combined.include?("--") && !combined.match?(/--.*--/m))

      ((start_index + 1)...paragraphs.length).each do |i|
        break unless apply_paragraph_step?(combined, paragraphs[i], state)
      end

      combined
    end

    # Returns true if iteration should continue, false to stop.
    def apply_paragraph_step?(combined, para, state)
      case classify_paragraph(para, state)
      when :continuation_toggle
        state.toggle!
        append!(combined, para)
      when :continuation
        append!(combined, para)
      when :list_member
        append!(combined, para)
        state.toggle! if opens_continuation_block?(para)
      else
        return false
      end
      true
    end

    def append!(combined, para)
      combined << "\n\n#{para}"
    end

    def opens_continuation_block?(para)
      para.include?("--") && !para.match?(/--.*--/m)
    end

    def classify_paragraph(para, state)
      return :continuation_toggle if para.match?(CONTINUATION_DASHES) || para.end_with?("--")
      return :continuation if state.in_block?
      return :list_member if starts_with_list?(para) || list_continuation?(para)

      :stop
    end

    # Mutable flag tracking whether we are inside a "-- ... --"
    # continuation block while walking paragraphs.
    class ContinuationState
      def initialize(in_block)
        @in_block = in_block
      end

      def in_block?
        @in_block
      end

      def toggle!
        @in_block = !@in_block
      end
    end
    private_constant :ContinuationState

    def list_continuation?(content)
      return false if content.nil? || content.empty?

      content.match?(CONTINUATION_PLUS) ||
        content.match?(CONTINUATION_DASHES) ||
        content.match?(INDENTED_PATTERN) ||
        content.start_with?("which", "where", "that")
    end

    def starts_with_list?(content)
      return false if content.nil? || content.empty?

      content.match?(BULLET_LIST_PATTERN) || content.match?(NUMBERED_LIST_PATTERN)
    end

    def only_keep_first_sentence(notes)
      notes.each do |note|
        next unless note&.content
        next if preserve_complete_structure?(note.content)

        new_content = note.content
          .split(SENTENCE_BREAK_NEWLINE).first.strip
          .split(SENTENCE_BREAK_SPACE).first.strip
        note.content = new_content.end_with?(".") ? new_content : "#{new_content}."
      end
    end

    def preserve_complete_structure?(content)
      return false if content.nil? || content.empty?

      lines = content.split("\n")
      return false unless first_line_is_header?(lines)
      return false if first_line_has_period?(lines.first.strip)

      remaining_content = lines[1..].join("\n")
      starts_with_list?(remaining_content.strip)
    end

    def first_line_is_header?(lines)
      lines.first&.strip&.end_with?(":") && lines.length > 1
    end

    def first_line_has_period?(first_line)
      first_line.count(".").positive?
    end

    def remove_see_content(notes)
      notes.each do |note|
        note.content = note.content.gsub(SEE_TAIL_PATTERN, "")
      end
    end

    def remove_redundant_note(notes)
      notes.reject do |note|
        note.content.match?(REDUNDANT_NOTE_REGEX) &&
          !note.content.include?("\n")
      end
    end

    def remove_invalid_references(notes)
      notes.reject do |note|
        note.content.include?(IMAGE_REF_SUBSTRING) ||
          note.content.match?(DOUBLE_ANGLE_PATTERN)
      end
    end

    def compare_with_definitions(notes, definitions)
      return [] if notes&.first&.content == definitions&.first&.content

      notes
    end

    def convert_xref(content)
      content
        .gsub(XREF_WITHOUT_DISPLAY) do |_match|
          full_ref = Regexp.last_match(1)
          display = full_ref.split(".").last
          xref_to_mention.call(full_ref, display)
        end
        .gsub(XREF_WITH_DISPLAY) do |_match|
          full_ref = Regexp.last_match(1)
          display = Regexp.last_match(2)
          xref_to_mention.call(full_ref, display)
        end
    end
  end
end
