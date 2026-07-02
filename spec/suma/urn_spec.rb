# frozen_string_literal: true

require "suma/urn"

RSpec.describe Suma::Urn do
  describe "#initialize" do
    it "strips a trailing wildcard to form the base URN" do
      urn = described_class.new("urn:iso:std:iso:10303:-2:ed-2:en:tech:*")
      expect(urn.to_s).to eq("urn:iso:std:iso:10303:-2:ed-2:en:tech")
    end

    it "leaves a wildcard-free URN unchanged" do
      urn = described_class.new("urn:iso:std:iso:10303:-2:ed-2:en:tech")
      expect(urn.to_s).to eq("urn:iso:std:iso:10303:-2:ed-2:en:tech")
    end

    it "only strips a single trailing :* — mid-string wildcards are preserved" do
      urn = described_class.new("urn:iso:std:*:10303:-2:ed-2:en:tech:*")
      expect(urn.to_s).to eq("urn:iso:std:*:10303:-2:ed-2:en:tech")
    end

    it "coerces non-string input via to_s" do
      coercible = Class.new do
        def to_s
          "urn:iso:std:iso:10303:-2:ed-2:en"
        end
      end.new
      urn = described_class.new(coercible)
      expect(urn.to_s).to eq("urn:iso:std:iso:10303:-2:ed-2:en")
    end

    it "produces an empty base from an empty input" do
      expect(described_class.new("").to_s).to eq("")
    end
  end

  describe "#wildcard" do
    it "appends :* to the base" do
      urn = described_class.new("urn:iso:std:iso:10303:-2:ed-2:en:tech")
      expect(urn.wildcard).to eq("urn:iso:std:iso:10303:-2:ed-2:en:tech:*")
    end

    it "is idempotent when constructed from a wildcard URN" do
      urn = described_class.new("urn:iso:std:iso:10303:-2:ed-2:en:tech:*")
      expect(urn.wildcard).to eq("urn:iso:std:iso:10303:-2:ed-2:en:tech:*")
    end
  end

  describe "#aliases" do
    it "returns the wildcard form as the only alias" do
      urn = described_class.new("urn:iso:std:iso:10303:-2:ed-2:en:tech")
      expect(urn.aliases).to eq(["urn:iso:std:iso:10303:-2:ed-2:en:tech:*"])
    end
  end

  describe "#for_schema" do
    it "composes a tech URN with the schema id" do
      urn = described_class.new("urn:iso:std:iso:10303:-2:ed-2:en")
      expect(urn.for_schema("action_schema"))
        .to eq("urn:iso:std:iso:10303:-2:ed-2:en:tech:action_schema")
    end
  end

  describe "#for_term" do
    it "composes a term URN with the concept identifier" do
      urn = described_class.new("urn:iso:std:iso:10303:-2:ed-2:en")
      expect(urn.for_term("express-language.entity"))
        .to eq("urn:iso:std:iso:10303:-2:ed-2:en:term:express-language.entity")
    end
  end

  describe "#for_entity" do
    it "composes a tech URN with the full entity reference" do
      urn = described_class.new("urn:iso:std:iso:10303:-2:ed-2:en")
      expect(urn.for_entity("action_schema.action"))
        .to eq("urn:iso:std:iso:10303:-2:ed-2:en:tech:action_schema.action")
    end
  end
end
