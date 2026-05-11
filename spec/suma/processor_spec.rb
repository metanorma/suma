# frozen_string_literal: true

require "suma/processor"

RSpec.describe Suma::Processor do
  describe "#initialize" do
    it "stores configuration" do
      processor = described_class.new(
        metanorma_yaml_path: "metanorma.yml",
        schemas_all_path: "schemas.yml",
        compile: false,
        output_directory: "_site",
      )

      expect(processor.metanorma_yaml_path).to eq("metanorma.yml")
      expect(processor.schemas_all_path).to eq("schemas.yml")
      expect(processor.compile_flag).to be(false)
      expect(processor.output_directory).to eq("_site")
    end

    it "defaults compile to true" do
      processor = described_class.new(
        metanorma_yaml_path: "metanorma.yml",
        schemas_all_path: "schemas.yml",
      )

      expect(processor.compile_flag).to be(true)
    end

    it "defaults output_directory to _site" do
      processor = described_class.new(
        metanorma_yaml_path: "metanorma.yml",
        schemas_all_path: "schemas.yml",
      )

      expect(processor.output_directory).to eq("_site")
    end
  end
end
