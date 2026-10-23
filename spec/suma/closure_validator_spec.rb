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

  describe "expression scoping" do
    let(:scoping_manifest) do
      File.expand_path("../fixtures/closure/scoping/schemas.yaml", __dir__)
    end

    it "resolves own and inherited attributes, QUERY variables, and bounds" do
      scoped_owners = %w[measured child_thing]
      violations = violations_for(scoping_manifest)
        .select { |v| scoped_owners.include?(v.owner_id) }
      expect(violations).to be_empty
    end

    it "still reports genuinely unknown identifiers" do
      ghosts = violations_for(scoping_manifest)
        .select { |v| v.owner_id == "haunted" }
      expect(ghosts.map(&:kind)).to eq(["where"])
      expect(ghosts.map(&:reference)).to eq(["ghost_attr"])
    end
  end

  describe "EXPRESS builtin functions" do
    let(:builtin_manifest) do
      File.expand_path("../fixtures/closure/builtin_functions/schemas.yaml",
                       __dir__)
    end

    it "resolves standard functions such as VALUE_UNIQUE" do
      good = violations_for(builtin_manifest)
        .select { |violation| violation.schema_id == "builtins" }
      expect(good).to be_empty
    end

    it "still reports unknown function calls" do
      ghost = violations_for(builtin_manifest)
        .select { |violation| violation.schema_id == "haunted_functions" }
      expect(ghost.map(&:kind)).to eq(["where"])
      expect(ghost.map(&:reference)).to eq(["NO_SUCH_FUNCTION"])
    end
  end

  describe "subtype constraints" do
    let(:constraint_manifest) do
      File.expand_path(
        "../fixtures/closure/subtype_constraints/schemas.yaml", __dir__
      )
    end

    it "resolves applies_to, total_over, and the body expression" do
      good = violations_for(constraint_manifest)
        .select { |violation| violation.schema_id == "sc_good" }
      expect(good).to be_empty
    end

    it "reports unresolvable constraint references by kind" do
      broken = violations_for(constraint_manifest)
        .select { |violation| violation.schema_id == "sc_broken" }

      expect(broken.map(&:kind)).to contain_exactly(
        "subtype_constraint", "total_over", "supertype", "supertype"
      )
      expect(broken.map(&:reference)).to contain_exactly(
        "missing_one", "missing_two", "missing_three", "missing_four"
      )
      expect(broken.map(&:owner_id)).to all(eq("sc_bad"))
    end
  end
end
