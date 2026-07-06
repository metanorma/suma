# frozen_string_literal: true

require "suma/note_processor"
require "glossarist"

RSpec.describe Suma::NoteProcessor do
  # The simplest xref_to_mention: renders {{urn,display}} strings without
  # needing a real Urn object. Tests focus on the cleaning pipeline,
  # not URN composition.
  let(:xref_to_mention) do
    ->(full_ref, display) { "{{urn:#{full_ref},#{display}}}" }
  end

  def with_definitions(content)
    [Glossarist::V3::DetailedDefinition.new(content: content)]
  end

  describe ".call with no remarks" do
    it "returns an empty array when remarks are nil" do
      result = described_class.call(nil,
                                    definitions: [],
                                    xref_to_mention: xref_to_mention)
      expect(result).to eq([])
    end

    it "returns an empty array when remarks are empty string" do
      result = described_class.call("",
                                    definitions: [],
                                    xref_to_mention: xref_to_mention)
      expect(result).to eq([])
    end
  end

  describe ".call with a simple sentence" do
    it "wraps the trimmed sentence in a single DetailedDefinition" do
      result = described_class.call("This is a note. More text.",
                                    definitions: [],
                                    xref_to_mention: xref_to_mention)
      expect(result.length).to eq(1)
      expect(result.first).to be_a(Glossarist::V3::DetailedDefinition)
      expect(result.first.content).to eq("This is a note.")
    end
  end

  describe "image-reference filtering" do
    it "drops a note whose content contains image::" do
      result = described_class.call("See image::diagram.svg[].",
                                    definitions: [],
                                    xref_to_mention: xref_to_mention)
      expect(result).to eq([])
    end
  end

  describe "double-angle-bracket filtering" do
    it "drops a note whose content contains a non-express <<...>> block" do
      # express xrefs are converted to {{urn,display}} mentions before the
      # filter runs; the filter catches other <<...>> blocks (e.g. asciidoc
      # cross-references that survived xref conversion).
      result = described_class.call("Refers to <<some_other_ref>>.",
                                    definitions: [],
                                    xref_to_mention: xref_to_mention)
      expect(result).to eq([])
    end
  end

  describe "see-tail stripping" do
    it "removes trailing (see ...) clauses" do
      result = described_class.call("Some content (see Section 4).",
                                    definitions: [],
                                    xref_to_mention: xref_to_mention)
      expect(result.first.content).to eq("Some content.")
    end
  end

  describe "redundant opening note suppression" do
    it "drops the 'An X is a type of {{...}}' opening sentence" do
      remark = "An action is a type of {{urn:foo,foo}}. Real content here."
      result = described_class.call(remark,
                                    definitions: [],
                                    xref_to_mention: xref_to_mention)
      # After trimming to first sentence, the note is "An action is a type
      # of {{urn:foo,foo}}." which matches REDUNDANT_NOTE_REGEX.
      expect(result).to eq([])
    end
  end

  describe "definition duplication" do
    it "returns empty when the first note equals the first definition" do
      definitions = with_definitions("Same content.")
      result = described_class.call("Same content.",
                                    definitions: definitions,
                                    xref_to_mention: xref_to_mention)
      expect(result).to eq([])
    end

    it "preserves the note when it differs from the first definition" do
      definitions = with_definitions("Different definition.")
      result = described_class.call("This is a note.",
                                    definitions: definitions,
                                    xref_to_mention: xref_to_mention)
      expect(result.length).to eq(1)
    end
  end

  describe "express xref → URN mention conversion" do
    it "converts <<express:schema.entity>> to a URN mention with the entity id as display" do
      result = described_class.call("Refers to <<express:action_schema.foo>>.",
                                    definitions: [],
                                    xref_to_mention: xref_to_mention)
      expect(result.first.content)
        .to include("{{urn:action_schema.foo,foo}}")
    end

    it "converts <<express:schema.entity,Display>> to a URN mention with the explicit display" do
      result = described_class.call("Uses <<express:action_schema.foo,Foo>>.",
                                    definitions: [],
                                    xref_to_mention: xref_to_mention)
      expect(result.first.content)
        .to include("{{urn:action_schema.foo,Foo}}")
    end
  end

  describe "multi-paragraph list preservation" do
    it "keeps a complete bulleted list following a colon-ended header" do
      remark = "The attributes are:\n\n* one\n* two\n* three"
      result = described_class.call(remark,
                                    definitions: [],
                                    xref_to_mention: xref_to_mention)
      expect(result.length).to eq(1)
      content = result.first.content
      expect(content).to include("The attributes are:")
      expect(content).to include("* one")
      expect(content).to include("* two")
      expect(content).to include("* three")
    end
  end

  describe "REDUNDANT_NOTE_REGEX constant" do
    it "is frozen" do
      expect(described_class::REDUNDANT_NOTE_REGEX).to be_frozen
    end
  end
end
