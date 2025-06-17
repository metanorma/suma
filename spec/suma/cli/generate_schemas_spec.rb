# frozen_string_literal: true

require "suma/cli"
require "suma/utils"
require "suma/cli/generate_schemas"

RSpec.describe Suma::Cli::GenerateSchemas do
  subject(:test_subject) { described_class.new }

  let(:metanorma_manifest_file) do
    "spec/fixtures/generate_schemas/metanorma-smrl-all.yml"
  end

  let(:schema_manifest_file) do
    "test-schemas-smrl-all.yml"
  end

  before do
    test_output = File.expand_path(schema_manifest_file)
    FileUtils.rm_f(test_output)
  end

  after do
    test_output = File.expand_path(schema_manifest_file)
    FileUtils.rm_f(test_output)
  end

  context "when input is invalid" do
    it "raises ENOENT error when METANORMA_MANIFEST_FILE not found" do
      expect do
        test_subject.generate_schemas("not-found.yaml", schema_manifest_file)
      end.to raise_error(Errno::ENOENT)
    end

    it "raises ArgumentError error when METANORMA_MANIFEST_FILE " \
       "is not a file" do
      expect do
        test_subject.generate_schemas(
          File.expand_path(".", __dir__),
          schema_manifest_file,
        )
      end.to raise_error(ArgumentError)
    end

    it "raises ArgumentError error when SCHEMA_MANIFEST_FILE " \
       "is not specified" do
      expect do
        test_subject.generate_schemas(metanorma_manifest_file)
      end.to raise_error(ArgumentError)
    end

    it "raises ArgumentError error when METANORMA_MANIFEST_FILE is not YAML" do
      expect do
        test_subject.generate_schemas("README.adoc", schema_manifest_file)
      end.to raise_error(ArgumentError)
    end

    it "raises ArgumentError error when SCHEMA_MANIFEST_FILE is not YAML" do
      expect do
        test_subject.generate_schemas(metanorma_manifest_file, "README.adoc")
      end.to raise_error(ArgumentError)
    end
  end

  context "when input is valid" do
    result_without_options = <<~RESULT
      ---
      schemas:
        Ap210_electronic_assembly_interconnect_and_packaging_design_arm:
          path: spec/fixtures/schemas/modules/ap210_electronic_assembly_interconnect_and_packaging_design/arm.exp
        Ap210_electronic_assembly_interconnect_and_packaging_design_arm_lf:
          path: spec/fixtures/schemas/modules/ap210_electronic_assembly_interconnect_and_packaging_design/arm_lf.exp
        Ap210_electronic_assembly_interconnect_and_packaging_design_mim:
          path: spec/fixtures/schemas/modules/ap210_electronic_assembly_interconnect_and_packaging_design/mim.exp
        Ap210_electronic_assembly_interconnect_and_packaging_design_mim_lf:
          path: spec/fixtures/schemas/modules/ap210_electronic_assembly_interconnect_and_packaging_design/mim_lf.exp
        action_schema:
          path: spec/fixtures/schemas/resources/action_schema/action_schema.exp
        application_context_schema:
          path: spec/fixtures/schemas/resources/application_context_schema/application_context_schema.exp
        approval_schema:
          path: spec/fixtures/schemas/resources/approval_schema/approval_schema.exp
        basic_attribute_schema:
          path: spec/fixtures/schemas/resources/basic_attribute_schema/basic_attribute_schema.exp
        certification_schema:
          path: spec/fixtures/schemas/resources/certification_schema/certification_schema.exp
        contract_schema:
          path: spec/fixtures/schemas/resources/contract_schema/contract_schema.exp
        date_time_schema:
          path: spec/fixtures/schemas/resources/date_time_schema/date_time_schema.exp
        document_schema:
          path: spec/fixtures/schemas/resources/document_schema/document_schema.exp
        effectivity_schema:
          path: spec/fixtures/schemas/resources/effectivity_schema/effectivity_schema.exp
        experience_schema:
          path: spec/fixtures/schemas/resources/experience_schema/experience_schema.exp
        external_reference_schema:
          path: spec/fixtures/schemas/resources/external_reference_schema/external_reference_schema.exp
        group_schema:
          path: spec/fixtures/schemas/resources/group_schema/group_schema.exp
        language_schema:
          path: spec/fixtures/schemas/resources/language_schema/language_schema.exp
        location_schema:
          path: spec/fixtures/schemas/resources/location_schema/location_schema.exp
        management_resources_schema:
          path: spec/fixtures/schemas/resources/management_resources_schema/management_resources_schema.exp
        measure_schema:
          path: spec/fixtures/schemas/resources/measure_schema/measure_schema.exp
        person_organization_schema:
          path: spec/fixtures/schemas/resources/person_organization_schema/person_organization_schema.exp
        product_definition_schema:
          path: spec/fixtures/schemas/resources/product_definition_schema/product_definition_schema.exp
        product_property_definition_schema:
          path: spec/fixtures/schemas/resources/product_property_definition_schema/product_property_definition_schema.exp
        product_property_representation_schema:
          path: spec/fixtures/schemas/resources/product_property_representation_schema/product_property_representation_schema.exp
        qualifications_schema:
          path: spec/fixtures/schemas/resources/qualifications_schema/qualifications_schema.exp
        security_classification_schema:
          path: spec/fixtures/schemas/resources/security_classification_schema/security_classification_schema.exp
        support_resource_schema:
          path: spec/fixtures/schemas/resources/support_resource_schema/support_resource_schema.exp
        uuid_attribute_schema:
          path: spec/fixtures/schemas/resources/uuid_attribute_schema/uuid_attribute_schema.exp
    RESULT

    result_with_options = <<~RESULT
      ---
      schemas:
        Ap210_electronic_assembly_interconnect_and_packaging_design_arm:
          path: spec/fixtures/schemas/modules/ap210_electronic_assembly_interconnect_and_packaging_design/arm.exp
        Ap210_electronic_assembly_interconnect_and_packaging_design_mim:
          path: spec/fixtures/schemas/modules/ap210_electronic_assembly_interconnect_and_packaging_design/mim.exp
        action_schema:
          path: spec/fixtures/schemas/resources/action_schema/action_schema.exp
        application_context_schema:
          path: spec/fixtures/schemas/resources/application_context_schema/application_context_schema.exp
        approval_schema:
          path: spec/fixtures/schemas/resources/approval_schema/approval_schema.exp
        basic_attribute_schema:
          path: spec/fixtures/schemas/resources/basic_attribute_schema/basic_attribute_schema.exp
        certification_schema:
          path: spec/fixtures/schemas/resources/certification_schema/certification_schema.exp
        contract_schema:
          path: spec/fixtures/schemas/resources/contract_schema/contract_schema.exp
        date_time_schema:
          path: spec/fixtures/schemas/resources/date_time_schema/date_time_schema.exp
        document_schema:
          path: spec/fixtures/schemas/resources/document_schema/document_schema.exp
        effectivity_schema:
          path: spec/fixtures/schemas/resources/effectivity_schema/effectivity_schema.exp
        experience_schema:
          path: spec/fixtures/schemas/resources/experience_schema/experience_schema.exp
        external_reference_schema:
          path: spec/fixtures/schemas/resources/external_reference_schema/external_reference_schema.exp
        group_schema:
          path: spec/fixtures/schemas/resources/group_schema/group_schema.exp
        language_schema:
          path: spec/fixtures/schemas/resources/language_schema/language_schema.exp
        location_schema:
          path: spec/fixtures/schemas/resources/location_schema/location_schema.exp
        management_resources_schema:
          path: spec/fixtures/schemas/resources/management_resources_schema/management_resources_schema.exp
        measure_schema:
          path: spec/fixtures/schemas/resources/measure_schema/measure_schema.exp
        person_organization_schema:
          path: spec/fixtures/schemas/resources/person_organization_schema/person_organization_schema.exp
        product_definition_schema:
          path: spec/fixtures/schemas/resources/product_definition_schema/product_definition_schema.exp
        product_property_definition_schema:
          path: spec/fixtures/schemas/resources/product_property_definition_schema/product_property_definition_schema.exp
        product_property_representation_schema:
          path: spec/fixtures/schemas/resources/product_property_representation_schema/product_property_representation_schema.exp
        qualifications_schema:
          path: spec/fixtures/schemas/resources/qualifications_schema/qualifications_schema.exp
        security_classification_schema:
          path: spec/fixtures/schemas/resources/security_classification_schema/security_classification_schema.exp
        support_resource_schema:
          path: spec/fixtures/schemas/resources/support_resource_schema/support_resource_schema.exp
        uuid_attribute_schema:
          path: spec/fixtures/schemas/resources/uuid_attribute_schema/uuid_attribute_schema.exp
    RESULT

    it "generates SCHEMA_MANIFEST_FILE without options" do
      test_subject.invoke(
        :generate_schemas,
        [metanorma_manifest_file, schema_manifest_file],
      )

      result = File.read(File.expand_path(schema_manifest_file))
      expect(result).to eq(result_without_options)
    end

    it "generates SCHEMA_MANIFEST_FILE with `exclude_paths: *_lf.exp`" do
      test_subject.invoke(
        :generate_schemas,
        [metanorma_manifest_file, schema_manifest_file],
        { exclude_paths: "*_lf.exp" },
      )
      result = File.read(File.expand_path(schema_manifest_file))
      expect(result).to eq(result_with_options)
    end
  end
end
