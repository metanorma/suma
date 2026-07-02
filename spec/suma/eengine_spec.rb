# frozen_string_literal: true

require "suma/eengine/errors"

RSpec.describe Suma::Eengine do
  describe "EengineError" do
    it "is a subclass of StandardError" do
      expect(described_class::EengineError).to be < StandardError
    end
  end

  describe "EengineNotFoundError" do
    it "is a subclass of EengineError" do
      expect(described_class::EengineNotFoundError).to be < described_class::EengineError
    end

    it "includes installation hints in the message" do
      error = described_class::EengineNotFoundError.new
      expect(error.message).to include("eengine not found in PATH")
      expect(error.message).to include("macOS")
      expect(error.message).to include("Linux")
    end
  end

  describe "ComparisonError" do
    it "is a subclass of EengineError" do
      expect(described_class::ComparisonError).to be < described_class::EengineError
    end

    it "exposes the captured stderr as a reader" do
      error = described_class::ComparisonError.new("boom", "stderr content")
      expect(error.message).to eq("boom")
      expect(error.stderr).to eq("stderr content")
    end

    it "defaults stderr to nil when only a message is supplied" do
      error = described_class::ComparisonError.new("boom")
      expect(error.stderr).to be_nil
    end
  end
end
