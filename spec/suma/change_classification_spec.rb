# frozen_string_literal: true

require "spec_helper"
require "suma/change_classification"

RSpec.describe Suma::ChangeClassification do
  describe ".classify" do
    {
      "added" => "additive",
      "removed" => "breaking",
      "modified" => "breaking",
      "mapping" => "editorial",
    }.each do |action, expected|
      it "classifies #{action} as #{expected}" do
        expect(described_class.classify(action: action)).to eq(expected)
      end
    end

    it "accepts symbols" do
      expect(described_class.classify(action: :added)).to eq("additive")
    end

    it "raises on an unknown action" do
      expect { described_class.classify(action: "renamed") }
        .to raise_error(Suma::Error, /unknown change action "renamed"/)
    end
  end

  describe "ALL" do
    it "lists the complete taxonomy, frozen" do
      expect(described_class::ALL).to eq(
        %w[additive compatible breaking editorial],
      )
      expect(described_class::ALL).to be_frozen
    end
  end
end
