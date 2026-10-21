# frozen_string_literal: true

require "spec_helper"
require "suma/schema_profile"

RSpec.describe Suma::SchemaProfile do
  describe ".default" do
    it "is the ISO 10303 profile" do
      expect(described_class.default).to eq(described_class::ISO_10303)
      expect(described_class.default.id).to eq("iso10303")
    end
  end

  describe ".fetch" do
    it "returns nil as the default profile" do
      expect(described_class.fetch(nil)).to eq(described_class.default)
    end

    it "accepts symbols, strings, and profile instances" do
      expect(described_class.fetch(:iso10303)).to eq(described_class::ISO_10303)
      expect(described_class.fetch("generic")).to eq(described_class::GENERIC)
      expect(described_class.fetch(described_class::GENERIC))
        .to eq(described_class::GENERIC)
    end

    it "raises on an unknown profile" do
      expect { described_class.fetch("stepml") }
        .to raise_error(Suma::Error, %r{unknown schema profile "stepml"})
    end
  end

  describe "#classify (iso10303)" do
    subject(:profile) { described_class::ISO_10303 }

    it "classifies module suffixes" do
      expect(profile.classify(id: "activity_arm", path: "x.exp"))
        .to eq(:module_arm)
      expect(profile.classify(id: "activity_mim", path: "x.exp"))
        .to eq(:module_mim)
      expect(profile.classify(id: "activity_bom", path: "x.exp"))
        .to eq(:business_object_model)
    end

    it "classifies conventional path segments" do
      expect(profile.classify(id: "topology", path: "r/resources/topology.exp"))
        .to eq(:resource)
      expect(profile.classify(id: "activity", path: "r/modules/activity.exp"))
        .to eq(:module_arm)
      expect(profile.classify(id: "core", path: "r/core_model/core.exp"))
        .to eq(:core_model)
    end

    it "classifies schemas under /applications/ as application protocols, " \
       "taking precedence over suffixes" do
      expect(profile.classify(id: "ap_gizmo_mim",
                              path: "s/applications/ap_gizmo/mim.exp"))
        .to eq(:application_protocol)
      expect(profile.classify(id: "ap_gizmo_arm",
                              path: "s/applications/ap_gizmo/arm.exp"))
        .to eq(:application_protocol)
    end

    it "preserves the historical suffix-over-path precedence elsewhere" do
      expect(profile.classify(id: "activity_arm",
                              path: "r/resources/activity.exp"))
        .to eq(:module_arm)
    end

    it "falls back to standalone" do
      expect(profile.classify(id: "misc", path: "misc.exp"))
        .to eq(:standalone)
    end
  end

  describe "#classify (generic)" do
    subject(:profile) { described_class::GENERIC }

    it "classifies nothing STEP-specific: every schema is standalone" do
      expect(profile.classify(id: "ifc_wall_arm", path: "x/modules/w.exp"))
        .to eq(:standalone)
      expect(profile.classify(id: "widget_schema", path: "x/resources/w.exp"))
        .to eq(:standalone)
      expect(profile.classify(id: nil, path: nil)).to eq(:standalone)
    end
  end

  describe "#classify (ifc)" do
    subject(:profile) { described_class::IFC }

    it "classifies every schema as standalone, whatever the path looks like" do
      aggregate_failures do
        expect(profile.classify(id: "ifc4", path: "IFC4.exp"))
          .to eq(:standalone)
        expect(profile.classify(id: "ifc4x3", path: "x/modules/w_arm.exp"))
          .to eq(:standalone)
      end
    end
  end

  describe "profile data" do
    it "keeps the ISO naming table and acronyms frozen" do
      expect(described_class::ISO_10303.suffix_labels).to be_frozen
      expect(described_class::ISO_10303.acronyms).to be_frozen
      expect(described_class::ISO_10303.acronyms).to include("ap")
    end

    it "gives the generic profile no suffix labels and no acronyms" do
      expect(described_class::GENERIC.suffix_labels).to eq({})
      expect(described_class::GENERIC.acronyms).to eq([])
    end

    it "declares the register category order per profile" do
      expect(described_class::ISO_10303.category_ids).to eq(
        %w[resources application_protocols modules
           business_object_models core_model other],
      )
      expect(described_class::GENERIC.category_ids).to eq(%w[other])
      expect(described_class::IFC.category_ids).to eq(%w[other])
    end
  end
end
