# frozen_string_literal: true

require "suma/cli"
require "suma/utils"
require "suma/cli/generate_schemas"

RSpec.describe Suma::Cli::GenerateSchemas do
  subject(:test_subject) { described_class.new }

  let(:metanorma_file_path) do
    "spec/fixtures/generate_schemas/metanorma-smrl-all.yml"
  end

  context "when input is invalid" do
    it "raises ENOENT error when file not found" do
      expect do
        test_subject.generate_schemas("not-found.yaml")
      end.to raise_error(Errno::ENOENT)
    end

    it "raises ArgumentError error when file is not a file" do
      expect do
        test_subject.generate_schemas(
          File.expand_path(".", __dir__),
        )
      end.to raise_error(ArgumentError)
    end

    it "raises ArgumentError error when the file is not a YAML file" do
      expect do
        test_subject.generate_schemas("README.adoc")
      end.to raise_error(ArgumentError)
    end
  end

  context "when input is valid" do
    result_without_options = <<~RESULT
      ---
      schemas:
        Ap210_electronic_assembly_interconnect_and_packaging_design_arm:
          path: ap210_electronic_assembly_interconnect_and_packaging_design/arm.exp
        Ap210_electronic_assembly_interconnect_and_packaging_design_arm_lf:
          path: ap210_electronic_assembly_interconnect_and_packaging_design/arm_lf.exp
        Ap210_electronic_assembly_interconnect_and_packaging_design_mim:
          path: ap210_electronic_assembly_interconnect_and_packaging_design/mim.exp
        Ap210_electronic_assembly_interconnect_and_packaging_design_mim_lf:
          path: ap210_electronic_assembly_interconnect_and_packaging_design/mim_lf.exp
        action_schema:
          path: action_schema/action_schema.exp
        application_context_schema:
          path: application_context_schema/application_context_schema.exp
        approval_schema:
          path: approval_schema/approval_schema.exp
        basic_attribute_schema:
          path: basic_attribute_schema/basic_attribute_schema.exp
        certification_schema:
          path: certification_schema/certification_schema.exp
        contract_schema:
          path: contract_schema/contract_schema.exp
        date_time_schema:
          path: date_time_schema/date_time_schema.exp
        document_schema:
          path: document_schema/document_schema.exp
        effectivity_schema:
          path: effectivity_schema/effectivity_schema.exp
        experience_schema:
          path: experience_schema/experience_schema.exp
        external_reference_schema:
          path: external_reference_schema/external_reference_schema.exp
        group_schema:
          path: group_schema/group_schema.exp
        language_schema:
          path: language_schema/language_schema.exp
        location_schema:
          path: location_schema/location_schema.exp
        management_resources_schema:
          path: management_resources_schema/management_resources_schema.exp
        measure_schema:
          path: measure_schema/measure_schema.exp
        person_organization_schema:
          path: person_organization_schema/person_organization_schema.exp
        product_definition_schema:
          path: product_definition_schema/product_definition_schema.exp
        product_property_definition_schema:
          path: product_property_definition_schema/product_property_definition_schema.exp
        product_property_representation_schema:
          path: product_property_representation_schema/product_property_representation_schema.exp
        qualifications_schema:
          path: qualifications_schema/qualifications_schema.exp
        security_classification_schema:
          path: security_classification_schema/security_classification_schema.exp
        support_resource_schema:
          path: support_resource_schema/support_resource_schema.exp
        uuid_attribute_schema:
          path: uuid_attribute_schema/uuid_attribute_schema.exp
    RESULT

    result_with_options = <<~RESULT
      ---
      schemas:
        Ap210_electronic_assembly_interconnect_and_packaging_design_arm:
          path: ap210_electronic_assembly_interconnect_and_packaging_design/arm.exp
        Ap210_electronic_assembly_interconnect_and_packaging_design_mim:
          path: ap210_electronic_assembly_interconnect_and_packaging_design/mim.exp
        action_schema:
          path: action_schema/action_schema.exp
        application_context_schema:
          path: application_context_schema/application_context_schema.exp
        approval_schema:
          path: approval_schema/approval_schema.exp
        basic_attribute_schema:
          path: basic_attribute_schema/basic_attribute_schema.exp
        certification_schema:
          path: certification_schema/certification_schema.exp
        contract_schema:
          path: contract_schema/contract_schema.exp
        date_time_schema:
          path: date_time_schema/date_time_schema.exp
        document_schema:
          path: document_schema/document_schema.exp
        effectivity_schema:
          path: effectivity_schema/effectivity_schema.exp
        experience_schema:
          path: experience_schema/experience_schema.exp
        external_reference_schema:
          path: external_reference_schema/external_reference_schema.exp
        group_schema:
          path: group_schema/group_schema.exp
        language_schema:
          path: language_schema/language_schema.exp
        location_schema:
          path: location_schema/location_schema.exp
        management_resources_schema:
          path: management_resources_schema/management_resources_schema.exp
        measure_schema:
          path: measure_schema/measure_schema.exp
        person_organization_schema:
          path: person_organization_schema/person_organization_schema.exp
        product_definition_schema:
          path: product_definition_schema/product_definition_schema.exp
        product_property_definition_schema:
          path: product_property_definition_schema/product_property_definition_schema.exp
        product_property_representation_schema:
          path: product_property_representation_schema/product_property_representation_schema.exp
        qualifications_schema:
          path: qualifications_schema/qualifications_schema.exp
        security_classification_schema:
          path: security_classification_schema/security_classification_schema.exp
        support_resource_schema:
          path: support_resource_schema/support_resource_schema.exp
        uuid_attribute_schema:
          path: uuid_attribute_schema/uuid_attribute_schema.exp
    RESULT

    it "generate_schemas METANORMA_YAML_FILE without options" do
      result = test_subject.invoke(:generate_schemas, [metanorma_file_path])
      expect(result).to eq(result_without_options)
    end

    it "generate_schemas METANORMA_YAML_FILE with options `exclude_lf: true`" do
      result = test_subject.invoke(
        :generate_schemas, [metanorma_file_path], { exclude_lf: true }
      )
      expect(result).to eq(result_with_options)
    end
  end
end
