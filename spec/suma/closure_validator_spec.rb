# frozen_string_literal: true

require "spec_helper"
require "suma/closure_validator"
require "suma/corpus_graph"

RSpec.describe Suma::ClosureValidator do
  let(:closure_manifest) do
    File.expand_path("../fixtures/closure/schemas.yaml", __dir__)
  end
  let(:good_manifest) do
    File.expand_path("../fixtures/ap_publication/schemas.yaml", __dir__)
  end

  def violations_for(manifest)
    graph = Suma::CorpusGraph.from_manifest(manifest)
    described_class.new(graph).validate_manifest(manifest)
  end

  describe "#validate_manifest" do
    it "reports zero violations for a closed corpus" do
      expect(violations_for(good_manifest)).to be_empty
    end

    it "reports every unresolved reference in a broken corpus" do
      violations = violations_for(closure_manifest)
      expect(violations.size).to eq(5)
      expect(violations.map(&:kind)).to contain_exactly(
        "interface", "underlying", "subtype_of", "attribute", "where"
      )
      expect(violations.map(&:reference)).to contain_exactly(
        "missing_interface", "nonexistent_type", "no_such_parent",
        "phantom_type", "missing_attribute"
      )
    end

    it "attributes each violation to its schema and owning declaration" do
      violations = violations_for(closure_manifest)
      violations.each do |violation|
        expect(violation.schema_id).to eq("broken_schema")
        expect(violation.owner_id).to match(/broken_(schema|entity|select)/)
        expect(violation.file).to end_with("broken.exp")
        expect(violation.reason).not_to be_empty
      end
    end

    it "approximates source lines for diagnostics" do
      violations = violations_for(closure_manifest)
      lines = violations.to_h { |v| [v.reference, v.line] }
      expect(lines["missing_interface"]).to eq(2)
      expect(lines["nonexistent_type"]).to eq(4)
      expect(lines["no_such_parent"]).to eq(8)
      expect(lines["phantom_type"]).to eq(9)
      expect(lines["missing_attribute"]).to eq(11)
    end
  end
end
