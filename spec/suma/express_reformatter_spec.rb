# frozen_string_literal: true

require "suma/express_reformatter"

RSpec.describe Suma::ExpressReformatter do
  let(:comment_one)   { "(*\"first comment block\n*)" }
  let(:comment_two)   { "(*\"second comment block\n*)" }

  describe ".call with no comments" do
    it "returns changed?: false" do
      result = described_class.call("SCHEMA foo;\nEND_SCHEMA;\n")
      expect(result.changed?).to be(false)
    end

    it "returns the original content unchanged" do
      original = "SCHEMA foo;\nEND_SCHEMA;\n"
      result = described_class.call(original)
      expect(result.content).to eq(original)
    end
  end

  describe ".call with one comment block" do
    it "extracts the comment and appends it to the end" do
      input = "SCHEMA foo;\n#{comment_one}\nEND_SCHEMA;\n"
      result = described_class.call(input)

      expect(result.changed?).to be(true)
      expect(result.content).to include("SCHEMA foo;")
      expect(result.content).to include("END_SCHEMA;")
      expect(result.content).to include(comment_one)
      # comment appears after END_SCHEMA; (i.e. at the end)
      end_idx = result.content.index("END_SCHEMA;")
      comment_idx = result.content.index(comment_one)
      expect(comment_idx).to be > end_idx
    end
  end

  describe ".call with multiple comment blocks" do
    it "extracts all comments and appends them in order" do
      input = "#{comment_one}SCHEMA foo;\n#{comment_two}END_SCHEMA;\n"
      result = described_class.call(input)

      expect(result.changed?).to be(true)
      expect(result.content).to include(comment_one)
      expect(result.content).to include(comment_two)
      # both comments appear after END_SCHEMA;
      end_idx = result.content.index("END_SCHEMA;")
      expect(result.content.index(comment_one)).to be > end_idx
      expect(result.content.index(comment_two)).to be > end_idx
      # preserved in source order
      first_idx = result.content.index(comment_one)
      second_idx = result.content.index(comment_two)
      expect(first_idx).to be < second_idx
    end
  end

  describe "idempotence" do
    it "produces no further changes when called on its own output" do
      input = "SCHEMA foo;\n#{comment_one}\nEND_SCHEMA;\n"
      once = described_class.call(input)
      twice = described_class.call(once.content)
      expect(twice.changed?).to be(false)
    end

    it "is stable across multiple applications" do
      input = "#{comment_one}SCHEMA foo;\n#{comment_two}\nEND_SCHEMA;\n"
      once = described_class.call(input).content
      twice = described_class.call(once).content
      expect(twice).to eq(once)
    end
  end

  describe "whitespace normalisation" do
    it "collapses runs of blank lines into single blank line" do
      input = "SCHEMA foo;\n\n\n\n#{comment_one}\nEND_SCHEMA;\n"
      result = described_class.call(input)

      expect(result.content.scan("\n\n\n")).to be_empty
    end

    it "reports no change when the only difference is whitespace" do
      # If both inputs already have their comments at the end (canonical
      # form) and differ only in blank-line runs, both should produce
      # changed?: false. Reformatting canonical content is a no-op.
      canonical = "SCHEMA foo;\nEND_SCHEMA;\n\n#{comment_one}\n"
      result = described_class.call(canonical)
      expect(result.changed?).to be(false)
    end
  end

  describe "Result struct" do
    it "is keyword-initialised" do
      result = described_class::Result.new(content: "x", changed?: true)
      expect(result.content).to eq("x")
      expect(result.changed?).to be(true)
    end

    it "returns content from content_or_nil when changed" do
      result = described_class::Result.new(content: "new", changed?: true)
      expect(result.content_or_nil).to eq("new")
    end

    it "returns nil from content_or_nil when unchanged" do
      result = described_class::Result.new(content: "old", changed?: false)
      expect(result.content_or_nil).to be_nil
    end
  end
end
