# frozen_string_literal: true

require "suma/term_classification"
require "suma/express_schema"

RSpec.describe Suma::TermClassification do
  describe "BY_TYPE" do
    it "is frozen" do
      expect(described_class::BY_TYPE).to be_frozen
    end

    it "covers every ExpressSchema::Type value exactly once" do
      type_values = [
        Suma::ExpressSchema::Type::RESOURCE,
        Suma::ExpressSchema::Type::MODULE_ARM,
        Suma::ExpressSchema::Type::MODULE_MIM,
        Suma::ExpressSchema::Type::BUSINESS_OBJECT_MODEL,
        Suma::ExpressSchema::Type::CORE_MODEL,
        Suma::ExpressSchema::Type::STANDALONE,
      ]
      declared = described_class::BY_TYPE.keys
      expect(declared.sort).to eq(type_values.sort)
    end

    it "freezes each value so callers cannot mutate shared state" do
      described_class::BY_TYPE.each_value do |classification|
        expect(classification).to be_frozen
      end
    end
  end

  describe "each classification" do
    it "exposes type, domain_label, entity_term, and entity_display" do
      arm = described_class::BY_TYPE[Suma::ExpressSchema::Type::MODULE_ARM]
      expect(arm.type).to eq(Suma::ExpressSchema::Type::MODULE_ARM)
      expect(arm.domain_label).to eq("application module")
      expect(arm.entity_term).to eq("general.application_object")
      expect(arm.entity_display).to eq("application object")
    end

    it "classifies module ARM as application module and application object" do
      arm = described_class::BY_TYPE[Suma::ExpressSchema::Type::MODULE_ARM]
      expect(arm.domain_label).to eq("application module")
      expect(arm.entity_display).to eq("application object")
    end

    it "classifies module MIM as application module but entity data type" do
      mim = described_class::BY_TYPE[Suma::ExpressSchema::Type::MODULE_MIM]
      expect(mim.domain_label).to eq("application module")
      expect(mim.entity_display).to eq("entity data type")
    end

    it "classifies resource, BOM, core_model, and standalone as resource " \
       "domain with entity data type" do
      [
        Suma::ExpressSchema::Type::RESOURCE,
        Suma::ExpressSchema::Type::BUSINESS_OBJECT_MODEL,
        Suma::ExpressSchema::Type::CORE_MODEL,
        Suma::ExpressSchema::Type::STANDALONE,
      ].each do |type|
        classification = described_class::BY_TYPE[type]
        expect(classification.domain_label).to eq("resource")
        expect(classification.entity_display).to eq("entity data type")
      end
    end
  end

  describe "#domain_for" do
    it "composes '<domain_label>: <schema_id>'" do
      arm = described_class::BY_TYPE[Suma::ExpressSchema::Type::MODULE_ARM]
      expect(arm.domain_for("activity_arm")).to eq("application module: activity_arm")
    end

    it "preserves the schema id verbatim (no normalisation)" do
      resource = described_class::BY_TYPE[Suma::ExpressSchema::Type::RESOURCE]
      expect(resource.domain_for("action_schema"))
        .to eq("resource: action_schema")
    end
  end

  describe ".for_schema" do
    it "classifies via id suffix when present" do
      arm = described_class.for_schema(id: "Activity_arm", path: "anywhere")
      expect(arm.type).to eq(Suma::ExpressSchema::Type::MODULE_ARM)
      expect(arm.domain_label).to eq("application module")

      mim = described_class.for_schema(id: "Activity_mim", path: "anywhere")
      expect(mim.type).to eq(Suma::ExpressSchema::Type::MODULE_MIM)

      bom = described_class.for_schema(id: "Activity_bom", path: "anywhere")
      expect(bom.type).to eq(Suma::ExpressSchema::Type::BUSINESS_OBJECT_MODEL)
    end

    it "falls back to path segments when id has no type suffix" do
      resource = described_class.for_schema(
        id: "action_schema",
        path: "schemas/resources/action_schema/action_schema.exp",
      )
      expect(resource.type).to eq(Suma::ExpressSchema::Type::RESOURCE)

      module_via_path = described_class.for_schema(
        id: "activity",
        path: "schemas/modules/activity/mim.exp",
      )
      expect(module_via_path.type).to eq(Suma::ExpressSchema::Type::MODULE_ARM)

      core = described_class.for_schema(
        id: "core",
        path: "schemas/core_model/core.exp",
      )
      expect(core.type).to eq(Suma::ExpressSchema::Type::CORE_MODEL)
    end

    it "returns STANDALONE for an unknown classification" do
      standalone = described_class.for_schema(
        id: "aic_csg",
        path: "schemas/aic_csg/aic_csg.exp",
      )
      expect(standalone.type).to eq(Suma::ExpressSchema::Type::STANDALONE)
      expect(standalone.domain_label).to eq("resource")
      expect(standalone.entity_display).to eq("entity data type")
    end

    it "prefers id suffix over path segment when they disagree" do
      # An _arm file in /resources/ is still a module ARM.
      arm = described_class.for_schema(
        id: "Foo_arm",
        path: "schemas/resources/foo/arm.exp",
      )
      expect(arm.type).to eq(Suma::ExpressSchema::Type::MODULE_ARM)
    end

    it "caches lookups via Type.classify (single classification path)" do
      # The contract: for_schema calls Type.classify exactly once.
      # This test pins that behaviour so future refactors don't
      # accidentally reintroduce a second classification channel.
      call_count = 0
      original = Suma::ExpressSchema::Type.method(:classify)
      allow(Suma::ExpressSchema::Type).to receive(:classify) do |**kwargs|
        call_count += 1
        original.call(**kwargs)
      end

      described_class.for_schema(id: "Activity_arm", path: "anywhere")
      expect(call_count).to eq(1)
    end
  end
end
