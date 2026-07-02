# frozen_string_literal: true

require "suma/schema_category"

RSpec.describe Suma::SchemaCategory do
  describe "ALL constant" do
    it "is frozen" do
      expect(described_class::ALL).to be_frozen
    end

    it "is ordered resources → modules → business_object_models → core_model → other" do
      expect(described_class::ALL.map(&:id)).to eq(
        %w[resources modules business_object_models core_model other],
      )
    end

    it "contains every category defined as a constant" do
      constants = %i[RESOURCES MODULES BUSINESS_OBJECT_MODELS CORE_MODEL OTHER]
      constant_categories = constants.map { |c| described_class.const_get(c) }
      expect(described_class::ALL).to eq(constant_categories)
    end
  end

  describe "each category" do
    it "exposes id, label, prefix, types, and directory readers" do
      resources = described_class::RESOURCES
      expect(resources.id).to eq("resources")
      expect(resources.label).to eq("Resources")
      expect(resources.prefix).to eq("Resource")
      expect(resources.types).to eq([Suma::ExpressSchema::Type::RESOURCE])
      expect(resources.directory).to eq("resources")
    end

    it "keeps the types array frozen so callers cannot mutate shared state" do
      expect(described_class::MODULES.types).to be_frozen
    end

    it "uses '.' as the directory for OTHER so files land at the root" do
      expect(described_class::OTHER.directory).to eq(".")
    end

    it "groups both module arm and mim under the modules category" do
      expect(described_class::MODULES.types).to contain_exactly(
        Suma::ExpressSchema::Type::MODULE_ARM,
        Suma::ExpressSchema::Type::MODULE_MIM,
      )
    end
  end

  describe "#member?" do
    it "returns true when the type belongs to the category" do
      expect(described_class::MODULES).to be_member(Suma::ExpressSchema::Type::MODULE_ARM)
      expect(described_class::MODULES).to be_member(Suma::ExpressSchema::Type::MODULE_MIM)
    end

    it "returns false when the type belongs to another category" do
      expect(described_class::RESOURCES).not_to be_member(Suma::ExpressSchema::Type::MODULE_ARM)
      expect(described_class::RESOURCES).not_to be_member(Suma::ExpressSchema::Type::STANDALONE)
    end
  end

  describe ".for_type" do
    it "maps every ExpressSchema::Type symbol to its category" do
      expect(described_class.for_type(Suma::ExpressSchema::Type::RESOURCE))
        .to be(described_class::RESOURCES)
      expect(described_class.for_type(Suma::ExpressSchema::Type::MODULE_ARM))
        .to be(described_class::MODULES)
      expect(described_class.for_type(Suma::ExpressSchema::Type::MODULE_MIM))
        .to be(described_class::MODULES)
      expect(described_class.for_type(Suma::ExpressSchema::Type::BUSINESS_OBJECT_MODEL))
        .to be(described_class::BUSINESS_OBJECT_MODELS)
      expect(described_class.for_type(Suma::ExpressSchema::Type::CORE_MODEL))
        .to be(described_class::CORE_MODEL)
      expect(described_class.for_type(Suma::ExpressSchema::Type::STANDALONE))
        .to be(described_class::OTHER)
    end

    it "falls back to OTHER for an unknown type" do
      expect(described_class.for_type(:nonexistent)).to be(described_class::OTHER)
    end
  end

  describe ".for_schema" do
    it "classifies by id suffix when present" do
      expect(described_class.for_schema(id: "Activity_arm", path: "anywhere"))
        .to be(described_class::MODULES)
      expect(described_class.for_schema(id: "Activity_mim", path: "anywhere"))
        .to be(described_class::MODULES)
      expect(described_class.for_schema(id: "Activity_bom", path: "anywhere"))
        .to be(described_class::BUSINESS_OBJECT_MODELS)
    end

    it "falls back to path segments when id has no type suffix" do
      expect(described_class.for_schema(id: "action_schema",
                                        path: "schemas/resources/action_schema/action_schema.exp"))
        .to be(described_class::RESOURCES)
      expect(described_class.for_schema(id: "activity",
                                        path: "schemas/modules/activity/mim.exp"))
        .to be(described_class::MODULES)
      expect(described_class.for_schema(id: "core",
                                        path: "schemas/core_model/core.exp"))
        .to be(described_class::CORE_MODEL)
    end

    it "returns OTHER when neither id nor path identifies a known category" do
      expect(described_class.for_schema(id: "aic_csg",
                                        path: "schemas/aic_csg/aic_csg.exp"))
        .to be(described_class::OTHER)
    end

    it "prefers id suffix over path segment when they disagree" do
      # id suffix wins: an _arm file in /resources/ is still a module arm
      expect(described_class.for_schema(id: "Foo_arm",
                                        path: "schemas/resources/foo/arm.exp"))
        .to be(described_class::MODULES)
    end
  end
end
