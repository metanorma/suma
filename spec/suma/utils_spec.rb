# frozen_string_literal: true

require "suma/utils"
require "stringio"

RSpec.describe Suma::Utils do
  let(:captured) { StringIO.new }

  before do
    described_class.output = captured
  end

  after do
    described_class.output = nil
  end

  describe ".output" do
    it "defaults to $stderr when nothing has been assigned" do
      described_class.output = nil
      expect(described_class.output).to eq($stderr)
    end

    it "returns the assigned IO object" do
      expect(described_class.output).to eq(captured)
    end
  end

  describe ".log" do
    it "writes the message with the [suma] prefix" do
      described_class.log("hello")
      expect(captured.string).to eq("[suma] hello\n")
    end

    it "always writes info-level messages" do
      described_class.log("info here", level: :info)
      expect(captured.string).to include("[suma] info here")
    end

    it "suppresses debug messages when SUMA_DEBUG is not set" do
      stub_const("ENV", ENV.to_h.except("SUMA_DEBUG"))
      described_class.log("noisy detail", level: :debug)
      expect(captured.string).to eq("")
    end

    it "writes debug messages when SUMA_DEBUG is set" do
      stub_const("ENV", ENV.to_h.merge("SUMA_DEBUG" => "1"))
      described_class.log("noisy detail", level: :debug)
      expect(captured.string).to include("[suma] noisy detail")
    end

    it "interpolates the message argument via to_s" do
      described_class.log(Pathname.new("/tmp/x"))
      expect(captured.string).to eq("[suma] /tmp/x\n")
    end
  end
end
