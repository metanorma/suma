# frozen_string_literal: true

require "suma/cli"
require "suma/utils"
require "suma/cli/validate_ascii"
require "tempfile"
require "stringio"

RSpec.describe Suma::Cli::ValidateAscii do
  subject(:validator) { described_class.new }

  # Helper method to capture stdout for testing
  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end

  describe "NonAsciiViolationCollection" do
    let(:collection) { Suma::Cli::NonAsciiViolationCollection.new }

    describe "#encode_iso_10303_11" do
      it "encodes ASCII characters correctly" do
        expect(collection.send(:encode_iso_10303_11, "A")).to eq("\"00000041\"")
      end

      it "encodes A-ring character correctly" do
        expect(collection.send(:encode_iso_10303_11, "Å")).to eq("\"000000C5\"")
      end

      it "encodes Japanese characters correctly" do
        # Test for 神戸 encoding
        expect(collection.send(:encode_iso_10303_11, "神")).to eq("\"0000795E\"")
        expect(collection.send(:encode_iso_10303_11, "戸")).to eq("\"00006238\"")
      end
    end

    describe "#process_non_ascii_char" do
      before do
        # Create a unicode_to_asciimath map for testing with common math symbols
        test_map = {
          "×" => "xx",
          "π" => "pi",
          "λ" => "lambda",
          "≤" => "le",
          "θ" => "theta",
          "φ" => "phi",
          "μ" => "mu",
          "ν" => "nu",
          "χ" => "chi",
          "σ" => "sigma",
        }
        allow(collection).to receive(:build_unicode_to_asciimath_map).and_return(test_map)
        collection.instance_variable_set(:@unicode_to_asciimath, test_map)
      end

      it "identifies common math symbols correctly" do
        # Test multiplication symbol
        result = collection.send(:process_non_ascii_char, "×")
        expect(result[:is_math]).to be true
        expect(result[:replacement]).to eq("xx")
        expect(result[:replacement_type]).to eq("asciimath")

        # Test pi symbol
        result = collection.send(:process_non_ascii_char, "π")
        expect(result[:is_math]).to be true
        expect(result[:replacement]).to eq("pi")
        expect(result[:replacement_type]).to eq("asciimath")

        # Test lambda symbol
        result = collection.send(:process_non_ascii_char, "λ")
        expect(result[:is_math]).to be true
        expect(result[:replacement]).to eq("lambda")
        expect(result[:replacement_type]).to eq("asciimath")

        # Test less than or equal symbol
        result = collection.send(:process_non_ascii_char, "≤")
        expect(result[:is_math]).to be true
        expect(result[:replacement]).to eq("le")
        expect(result[:replacement_type]).to eq("asciimath")
      end

      it "encodes non-math symbols with ISO 10303-11" do
        result = collection.send(:process_non_ascii_char, "神")
        expect(result[:is_math]).to be false
        expect(result[:replacement]).to eq("\"0000795E\"")
        expect(result[:replacement_type]).to eq("iso-10303-11")
      end
    end
  end

  describe "#validate_ascii" do
    let(:temp_file) { Tempfile.new(["test", ".exp"]) }

    before do
      temp_file.write("ENTITY test_entity;\n  name: STRING; -- 神戸 Japanese characters\nEND_ENTITY;\n")
      temp_file.close
    end

    after do
      temp_file.unlink
    end

    it "detects and reports non-ASCII characters" do
      output = capture_stdout do
        validator.validate_ascii(temp_file.path)
      end

      # Verify output contains correct information
      expect(output).to include("神")
      expect(output).to include("戸")
      expect(output).to include("\"0000795E\"")
      expect(output).to include("\"00006238\"")
    end

    it "raises ENOENT error for non-existent file" do
      expect do
        validator.validate_ascii("not-found.exp")
      end.to raise_error(Errno::ENOENT)
    end

    it "raises ArgumentError for non-EXPRESS file" do
      non_exp_file = Tempfile.new(["test", ".txt"])
      begin
        expect do
          validator.validate_ascii(non_exp_file.path)
        end.to raise_error(ArgumentError)
      ensure
        non_exp_file.unlink
      end
    end
  end
end
