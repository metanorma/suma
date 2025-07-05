# frozen_string_literal: true

require "suma/cli"
require "suma/utils"
require "suma/cli/extract_terms"

RSpec.describe Suma::Cli::ExtractTerms do
  subject(:test_subject) { described_class.new }

  let(:schema_manifest_file) do
    File.expand_path(
      "../../fixtures/extract_terms/schemas-smrl-all.yml", __dir__
    )
  end

  let(:schema_manifest_file_no_files) do
    File.expand_path(
      "../../fixtures/extract_terms/schemas-smrl-no-files.yml", __dir__
    )
  end

  let(:test_output_path) do
    File.expand_path("test-glossarist-v2-dataset", __dir__)
  end

  before do
    FileUtils.rm_rf(test_output_path)
  end

  after do
    FileUtils.rm_rf(test_output_path)
  end

  context "when input is invalid" do
    it "raises ENOENT error when file not found" do
      expect do
        test_subject.invoke(:extract_terms, ["not-found.yml", test_output_path])
      end.to raise_error(Errno::ENOENT)
    end

    it "raises InvalidSchemaManifestError when file is not valid YAML" do
      expect do
        test_subject.invoke(
          :extract_terms,
          [
            File.expand_path("extract_terms_spec.rb", __dir__),
            test_output_path,
          ],
        )
      end.to raise_error(Expressir::InvalidSchemaManifestError)
    end

    it "raises ENOENT error when no files found" do
      expect do
        test_subject.invoke(
          :extract_terms,
          [schema_manifest_file_no_files, test_output_path],
        )
      end.to raise_error(Errno::ENOENT)
    end
  end

  context "when input is valid `schema_manifest_file`" do
    it "creates one concept per entity with correct identifiers" do
      result_collections = test_subject.invoke(
        :extract_terms, [schema_manifest_file, test_output_path]
      )

      # Verify we have 3 collections (one per schema)
      expect(result_collections.length).to eq(3)

      # Check Activity_arm schema - should have 4 entities
      activity_arm_collection = result_collections.find { |c|
        c.managed_concepts.any? { |mc| mc.data.id.start_with?("Activity_arm.") }
      }
      expect(activity_arm_collection.managed_concepts.length).to eq(4)

      expected_arm_ids = [
        "Activity_arm.Activity",
        "Activity_arm.Activity_relationship",
        "Activity_arm.Activity_status",
        "Activity_arm.Applied_activity_assignment"
      ]
      actual_arm_ids = activity_arm_collection.managed_concepts.map { |mc| mc.data.id }.sort
      expect(actual_arm_ids).to eq(expected_arm_ids.sort)

      # Check Activity_mim schema - should have 1 entity
      activity_mim_collection = result_collections.find { |c|
        c.managed_concepts.any? { |mc| mc.data.id.start_with?("Activity_mim.") }
      }
      expect(activity_mim_collection.managed_concepts.length).to eq(1)
      expect(activity_mim_collection.managed_concepts.first.data.id).to eq("Activity_mim.applied_action_assignment")

      # Check action_schema - should have 17 entities
      action_schema_collection = result_collections.find { |c|
        c.managed_concepts.any? { |mc| mc.data.id.start_with?("action_schema.") }
      }
      expect(action_schema_collection.managed_concepts.length).to eq(17)

      # Verify that all concepts have the correct identifier format
      all_concepts = result_collections.flat_map(&:managed_concepts)
      all_concepts.each do |concept|
        expect(concept.data.id).to match(/\A\w+\.\w+\z/), "Expected format 'schema.entity' but got '#{concept.data.id}'"
      end

      # Verify that concepts have proper terms (entity names)
      activity_concept = activity_arm_collection.managed_concepts.find { |mc| mc.data.id == "Activity_arm.Activity" }
      localized_concept = activity_concept.data.localizations["eng"]
      expect(localized_concept.data.terms.first.designation).to eq("Activity")

      # Verify that all concepts from the same schema share the same citation
      activity_arm_collection.managed_concepts.each do |concept|
        localized_concept = concept.data.localizations["eng"]
        expect(localized_concept.data.sources.length).to eq(1)
        expect(localized_concept.data.sources.first.origin.text).to eq("ISO 10303")
      end
    end
  end
end
