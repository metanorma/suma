# frozen_string_literal: true

require "spec_helper"
require "suma/schema_naming"

RSpec.describe Suma::SchemaNaming do
  describe ".display_name" do
    {
      # Resource schemas — suffix stripped, no label
      "topology_schema" => "Topology",
      "action_schema" => "Action",
      "structural_response_representation_schema" => "Structural Response Representation",
      "aic_advanced_brep" => "AIC Advanced Brep",

      # Module schemas — suffix stripped, label appended
      "Activity_arm" => "Activity (ARM)",
      "Activity_mim" => "Activity (MIM)",
      "Activity_method_assignment_mim" => "Activity Method Assignment (MIM)",

      # Function words lowercased (except first position)
      "Activity_as_realized_arm" => "Activity as Realized (ARM)",
      "Analysis_product_relationships_arm" => "Analysis Product Relationships (ARM)",

      # Acronyms preserved
      "aic_geometrically_bounded_2d_wireframe" => "AIC Geometrically Bounded 2D Wireframe",
      "Aec_service_life_arm" => "AEC Service Life (ARM)",

      # Standalone (no suffix)
      "aic_csg" => "AIC CSG",
    }.each do |input, expected|
      it "converts #{input.inspect} → #{expected.inspect}" do
        expect(described_class.display_name(input)).to eq(expected)
      end
    end
  end

  describe ".prefixed_name" do
    it "prefixes resource schemas with 'Resource'" do
      result = described_class.prefixed_name(
        "topology_schema",
        path: "schemas/resources/topology_schema/topology_schema.exp",
      )
      expect(result).to eq("Resource: Topology")
    end

    it "prefixes ARM modules with 'Module'" do
      result = described_class.prefixed_name(
        "Activity_arm",
        path: "schemas/modules/activity/arm.exp",
      )
      expect(result).to eq("Module: Activity (ARM)")
    end

    it "prefixes MIM modules with 'Module'" do
      result = described_class.prefixed_name(
        "Activity_method_assignment_mim",
        path: "schemas/modules/activity_method_assignment/mim.exp",
      )
      expect(result).to eq("Module: Activity Method Assignment (MIM)")
    end
  end

  describe ".display_name edge cases" do
    {
      "" => "",
      "a" => "A",
      "X" => "X",
      "_foo" => "Foo",
      "foo_" => "Foo",
      "foo__bar" => "Foo Bar",
      "AIC" => "AIC",
      "aic" => "AIC",
      "camel_Case" => "Camel Case",
      "ISO_10303" => "Iso 10303",
    }.each do |input, expected|
      it "converts #{input.inspect} → #{expected.inspect}" do
        expect(described_class.display_name(input)).to eq(expected)
      end
    end
  end

  describe "suffix decomposition" do
    it "strips _schema silently" do
      expect(described_class.display_name("foo_schema")).to eq("Foo")
    end

    it "labels _arm" do
      expect(described_class.display_name("foo_arm")).to eq("Foo (ARM)")
    end

    it "labels _mim" do
      expect(described_class.display_name("foo_mim")).to eq("Foo (MIM)")
    end

    it "labels _bom" do
      expect(described_class.display_name("foo_bom")).to eq("Foo (BOM)")
    end

    it "leaves unknown suffixes intact" do
      expect(described_class.display_name("foo_xyz")).to eq("Foo Xyz")
    end
  end

  describe ".prefixed_name edge cases" do
    it "uses the standalone prefix when path is nil" do
      expect(described_class.prefixed_name("custom_id", path: nil))
        .to eq("Schema: Custom ID")
    end

    it "classifies by id alone when path is nil" do
      expect(described_class.prefixed_name("topology_schema", path: nil))
        .to eq("Schema: Topology")
    end
  end

  describe ".category_prefix" do
    {
      resource: "Resource",
      module_arm: "Module",
      module_mim: "Module",
      business_object_model: "Business Object Model",
      core_model: "Core Model",
      standalone: "Schema",
    }.each do |type, expected|
      it "returns #{expected.inspect} for :#{type}" do
        expect(described_class.category_prefix(type)).to eq(expected)
      end
    end
  end
end
