# frozen_string_literal: true

require "spec_helper"
require "suma/term_extractor"
require "tmpdir"

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
      extractor = described_class.new(schema_manifest_file, test_output_path,
                                      urn: "urn:iso:std:iso:10303:-2:ed-2:en")
      results = extractor.call

      expect(results).to be_an(Array)
      expect(results.length).to eq(3)
      expect(results).to all(be_a(Glossarist::ManagedConceptCollection))
    end

    it "creates concepts with correct schema-prefixed identifiers" do
      extractor = described_class.new(schema_manifest_file, test_output_path,
                                      urn: "urn:iso:std:iso:10303:-2:ed-2:en")
      results = extractor.call

      all_concepts = results.flat_map(&:managed_concepts)
      all_concepts.each do |concept|
        expect(concept.data.id).to match(/\A\w+\.\w+\z/)
      end
    end

    it "assigns UUIDv5-format strings to ManagedConcept#uuid" do
      extractor = described_class.new(schema_manifest_file, test_output_path,
                                      urn: "urn:iso:std:iso:10303:-2:ed-2:en")
      results = extractor.call

      all_concepts = results.flat_map(&:managed_concepts)
      all_concepts.each do |concept|
        expect(concept.uuid).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
        expect(concept.uuid).not_to eq(concept.id)
      end
    end

    it "produces stable UUIDs across runs for the same concept id" do
      first_run = described_class.new(schema_manifest_file, test_output_path,
                                      urn: "urn:iso:std:iso:10303:-2:ed-2:en").call
      first_uuids = first_run.flat_map(&:managed_concepts).to_h do |c|
        [c.data.id, c.uuid]
      end

      second_run = described_class.new(schema_manifest_file, test_output_path,
                                       urn: "urn:iso:std:iso:10303:-2:ed-2:en").call
      second_uuids = second_run.flat_map(&:managed_concepts).to_h do |c|
        [c.data.id, c.uuid]
      end

      expect(second_uuids).to eq(first_uuids)
    end

    it "writes output files to the specified directory" do
      extractor = described_class.new(schema_manifest_file, test_output_path,
                                      urn: "urn:iso:std:iso:10303:-2:ed-2:en")
      extractor.call

      expect(Dir.glob(File.join(test_output_path, "**",
                                "*.yaml")).any?).to be true
    end

    it "raises ENOENT when the manifest file does not exist" do
      extractor = described_class.new("/nonexistent/path.yml", test_output_path,
                                      urn: "urn:iso:std:iso:10303:-2:ed-2:en")
      expect { extractor.call }.to raise_error(Errno::ENOENT)
    end

    it "raises ENOENT when the manifest path is a directory" do
      extractor = described_class.new(test_output_path, test_output_path,
                                      urn: "urn:iso:std:iso:10303:-2:ed-2:en")
      expect { extractor.call }.to raise_error(Errno::ENOENT)
    end

    it "raises an error when manifest has no schema files" do
      no_files_manifest = File.expand_path(
        "../fixtures/extract_terms/schemas-smrl-no-files.yml", __dir__
      )
      extractor = described_class.new(no_files_manifest, test_output_path,
                                      urn: "urn:iso:std:iso:10303:-2:ed-2:en")
      expect { extractor.call }.to raise_error(StandardError)
    end
  end
end
