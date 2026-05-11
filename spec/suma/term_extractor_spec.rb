# frozen_string_literal: true

require "suma/term_extractor"

RSpec.describe Suma::TermExtractor do
  let(:schema_manifest_file) do
    File.expand_path("../fixtures/extract_terms/schemas-smrl-all.yml", __dir__)
  end

  let(:test_output_path) do
    Dir.mktmpdir("suma_term_extractor_test")
  end

  after do
    FileUtils.rm_rf(test_output_path)
  end

  describe "#call" do
    it "extracts terms for each schema in the manifest" do
      extractor = described_class.new(schema_manifest_file, test_output_path)
      results = extractor.call

      expect(results).to be_an(Array)
      expect(results.length).to eq(3)
      expect(results).to all(be_a(Glossarist::ManagedConceptCollection))
    end

    it "creates concepts with correct schema-prefixed identifiers" do
      extractor = described_class.new(schema_manifest_file, test_output_path)
      results = extractor.call

      all_concepts = results.flat_map(&:managed_concepts)
      all_concepts.each do |concept|
        expect(concept.data.id).to match(/\A\w+\.\w+\z/)
      end
    end

    it "writes output files to the specified directory" do
      extractor = described_class.new(schema_manifest_file, test_output_path)
      extractor.call

      expect(Dir.glob(File.join(test_output_path, "**", "*.yaml")).any?).to be true
    end

    it "raises an error when manifest file does not exist" do
      extractor = described_class.new("/nonexistent/path.yml", test_output_path)
      expect { extractor.call }.to raise_error(StandardError)
    end

    it "raises an error when manifest has no schema files" do
      no_files_manifest = File.expand_path(
        "../fixtures/extract_terms/schemas-smrl-no-files.yml", __dir__
      )
      extractor = described_class.new(no_files_manifest, test_output_path)
      expect { extractor.call }.to raise_error(StandardError)
    end
  end
end
