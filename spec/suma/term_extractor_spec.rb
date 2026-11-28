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
        expect(concept.uuid).not_to eq(concept.data.id)
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

    it "keys output files by concept identifier, keeping the UUID inside" do
      extractor = described_class.new(schema_manifest_file, test_output_path,
                                      urn: "urn:iso:std:iso:10303:-2:ed-2:en")
      concepts = extractor.call.flat_map(&:managed_concepts)

      concepts.each do |concept|
        path = File.join(test_output_path, "#{concept.data.id}.yaml")
        expect(File).to exist(path)

        content = File.read(path)
        expect(content).to include("identifier: #{concept.data.id}")
        expect(content).to include(concept.uuid)
      end
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

  describe "provenance" do
    let(:urn_base) { "urn:iso:std:iso:10303:-2:ed-2:en" }

    it "records the schema, entity URN, and edition on each concept" do
      extractor = described_class.new(
        schema_manifest_file, test_output_path, urn: urn_base, edition: 3
      )
      concept = extractor.call.first.managed_concepts.first
      source = concept.localization("eng").data.sources.first

      expect(source.origin.ref.source)
        .to eq("#{urn_base}:tech:Activity_arm")
      expect(source.origin.ref.version).to eq("3")
      expect(source.sourced_from.first.ref.source)
        .to eq("#{urn_base}:tech:#{concept.data.id}")
      expect(source.sourced_from.first.ref.version).to eq("3")
    end
  end

  describe "multilingual linkage" do
    let(:urn_base) { "urn:iso:std:iso:10303:-2:ed-2:en" }

    it "stores linked localizations under one managed concept" do
      extractor = described_class.new(
        schema_manifest_file, test_output_path, urn: urn_base,
                                                language_codes: %w[fra deu]
      )
      concept = extractor.call.first.managed_concepts.first

      expect(concept.data.localizations.keys)
        .to contain_exactly("eng", "fra", "deu")
      localized_ids = concept.data.localized_concepts
      expect(localized_ids.keys).to contain_exactly("eng", "fra", "deu")
      expect(localized_ids.values.uniq.length).to eq(3)

      english = concept.localization("eng").data
      french = concept.localization("fra").data
      expect(french.language_code).to eq("fra")
      expect(french.terms.first.designation)
        .to eq(english.terms.first.designation)
      expect(french.definition.first.content)
        .to eq(english.definition.first.content)
    end

    it "writes all localizations to one document" do
      extractor = described_class.new(
        schema_manifest_file, test_output_path, urn: urn_base,
                                                language_codes: %w[fra]
      )
      extractor.call
      document = Glossarist::V3::ConceptDocument.from_yamls(
        File.read(Dir[File.join(test_output_path, "*.yaml")].first),
      )
      expect(document.concept.data.localized_concepts.keys)
        .to contain_exactly("eng", "fra")
      expect(document.localizations.map { |l| l.data.language_code })
        .to contain_exactly("eng", "fra")
    end

    it "qualifies imported supertype citations with the declaring schema" do
      # applied_action_assignment is SUBTYPE OF (action_assignment); the
      # fixture imports action_assignment from management_resources_schema
      # via a USE FROM item list. The citation must name the declaring
      # schema, not the citing one (iso-10303#835): the citing schema has
      # no anchor for the declaration, so the rendered reference dies.
      extractor = described_class.new(schema_manifest_file, test_output_path,
                                      urn: "urn:iso:std:iso:10303:-2:ed-2:en")
      results = extractor.call

      concept = results.flat_map(&:managed_concepts)
        .find { |c| c.data.id == "Activity_mim.applied_action_assignment" }
      expect(concept).not_to be_nil

      content = concept.localization("eng").data.definition.first.content
      expect(content).to include("tech:management_resources_schema.action_assignment")
      expect(content).not_to include("tech:Activity_mim.action_assignment")
    end

    describe "transitive declaring-schema resolution (iso-10303#835)" do
      let(:chain_manifest_file) do
        File.expand_path("../fixtures/extract_terms/schemas-chain.yml", __dir__)
      end

      def chain_concepts
        extractor = described_class.new(chain_manifest_file, test_output_path,
                                        urn: "urn:iso:std:iso:10303:-2:ed-2:en")
        extractor.call.flat_map(&:managed_concepts)
      end

      def concept_content(id)
        concept = chain_concepts.find { |c| c.data.id == id }
        expect(concept).not_to be_nil
        concept.localization("eng").data.definition.first.content
      end

      it "resolves a declaration two bare USE FROMs away through branching" do
        # outer_thing SUBTYPE OF (deep_thing); Outer_arm barely uses
        # Middle_arm, which barely uses Deep_arm AND Other_arm — both
        # sibling branches must be searched, and only Deep_arm declares
        # the entity (the Primitive_solids_arm shape from #835).
        content = concept_content("Outer_arm.outer_thing")
        expect(content).to include("tech:Deep_arm.deep_thing")
        expect(content).not_to include("tech:Middle_arm.deep_thing")
        expect(content).not_to include("tech:Outer_arm.deep_thing")
      end

      it "emits target unresolved when sibling branches disagree" do
        # Outer_ambiguous_arm barely uses Deep_arm and Twin_arm, and BOTH
        # declare deep_thing — no single declarer emerges, so no owner is
        # invented and no xref is emitted (WG 12: the literal, not a guess).
        content = concept_content("Outer_ambiguous_arm.ambiguous_thing")
        aggregate_failures do
          expect(content).to include("that is a type of target unresolved")
          expect(content).not_to include("tech:Outer_ambiguous_arm.deep_thing")
          expect(content).not_to include("tech:Deep_arm.deep_thing")
          expect(content).not_to include("tech:Twin_arm.deep_thing")
        end
      end

      def pair_concepts
        manifest = File.expand_path(
          "../fixtures/extract_terms/schemas-pair.yml", __dir__
        )
        extractor = described_class.new(
          manifest, test_output_path, urn: "urn:iso:std:iso:10303:-2:ed-2:en"
        )
        extractor.call.flat_map(&:managed_concepts)
      end

      def pair_concept_content(id)
        concept = pair_concepts.find { |c| c.data.id == id }
        expect(concept).not_to be_nil
        concept.localization("eng").data.definition.first.content
      end

      it "emits target unresolved for a bare name with no interface edge" do
        # Pair_arm cites sibling_thing (SUBTYPE OF) with NO interface edge
        # to Pair_mim — the _arm/_mim shape. The manifest-wide sibling
        # scan that used to bind the citation to Pair_mim is gone (WG 12:
        # a same-spelling declaration elsewhere is not a resolution), so
        # the citation carries no xref at all.
        content = pair_concept_content("Pair_arm.paired_thing")
        aggregate_failures do
          expect(content).to include("that is a type of target unresolved")
          expect(content).not_to include("tech:Pair_mim.sibling_thing")
          expect(content).not_to include("tech:Pair_arm.sibling_thing")
        end
      end

      it "emits target unresolved when several siblings declare the name" do
        # Pair_mim AND Pair_twin both declare alt_thing — two declarers is
        # not a resolution, and the interface walk finds none, so the
        # citation stays unresolved rather than guessing an owner.
        content = pair_concept_content("Pair_arm.ambiguous_thing")
        aggregate_failures do
          expect(content).to include("that is a type of target unresolved")
          expect(content).not_to include("tech:Pair_arm.alt_thing")
          expect(content).not_to include("tech:Pair_mim.alt_thing")
          expect(content).not_to include("tech:Pair_twin.alt_thing")
        end
      end

      it "still trusts a USE FROM item list without walking" do
        # The #187 case, pinned: applied_action_assignment's supertype is
        # named in an item list (USE FROM management_resources_schema
        # (action_assignment)) — an item list is a terminal claim, so the
        # declaration needs no sibling parse even though the bare
        # USE FROM Activity_method_mim sits in the same fixture outside
        # the manifest.
        extractor = described_class.new(schema_manifest_file, test_output_path,
                                        urn: "urn:iso:std:iso:10303:-2:ed-2:en")
        results = extractor.call

        concept = results.flat_map(&:managed_concepts)
          .find { |c| c.data.id == "Activity_mim.applied_action_assignment" }
        content = concept.localization("eng").data.definition.first.content
        expect(content).to include("tech:management_resources_schema.action_assignment")
      end

      it "resolves through a REFERENCE FROM item list" do
        # The 300-row shape from the 2026-11-12 measurement: resource
        # schemas import through REFERENCE FROM, and those edges carry
        # the declaring schema the same way USE FROM ones do.
        content = concept_content("Ref_arm.ref_thing")
        expect(content).to include("tech:Deep_arm.deep_thing")
        expect(content).not_to include("tech:Ref_arm.deep_thing")
      end
    end

    describe "interface-only resolution (WG 12 position on 0.5.42)" do
      let(:case_manifest_file) do
        File.expand_path("../fixtures/extract_terms/schemas-case.yml", __dir__)
      end

      def case_concepts
        extractor = described_class.new(case_manifest_file, test_output_path,
                                        urn: "urn:iso:std:iso:10303:-2:ed-2:en")
        extractor.call.flat_map(&:managed_concepts)
      end

      def case_concept_content(id)
        concept = case_concepts.find { |c| c.data.id == id }
        expect(concept).not_to be_nil
        concept.localization("eng").data.definition.first.content
      end

      it "does not bind a case-variant supertype to a same-spelling sibling" do
        # mismatched_thing cites gadget; the USE FROM target Decl_arm
        # declares Gadget (case-insensitive in EXPRESS, exact-match in the
        # walk), while Other_schema declares gadget with no interface edge
        # from Citing_arm. The manifest-wide sibling scan used to bind
        # the citation to Other_schema; per WG 12 it stays unresolved (the
        # kinematic_structure screw_pair shape, iso-10303#835).
        content = case_concept_content("Citing_arm.mismatched_thing")
        aggregate_failures do
          expect(content).to include("that is a type of target unresolved")
          expect(content).not_to include("tech:Other_schema.gadget")
          expect(content).not_to include("tech:Decl_arm.gadget")
        end
      end

      it "still resolves a declaration reachable through USE FROM" do
        # matched_thing SUBTYPE OF (Holder); bare USE FROM Decl_arm, and
        # Decl_arm declares Holder exactly — the interface walk qualifies
        # the citation with the declaring schema as before.
        content = case_concept_content("Citing_arm.matched_thing")
        expect(content).to include("tech:Decl_arm.Holder")
      end
    end

    describe "note xref re-qualification (iso-10303#848)" do
      let(:note_manifest_file) do
        File.expand_path("../fixtures/extract_terms/schemas-chain.yml", __dir__)
      end

      def concept_with_id(id)
        described_class
          .new(note_manifest_file, test_output_path,
               urn: "urn:iso:std:iso:10303:-2:ed-2:en")
          .call.flat_map(&:managed_concepts)
          .find { |c| c.data.id == id }
      end

      def outer_note
        concept = concept_with_id("Outer_arm.outer_thing")
        expect(concept).not_to be_nil
        concept.localization("eng").data.notes.map(&:content).join(" ")
      end

      it "re-qualifies a note xref the citing schema only imports" do
        notes = outer_note
        # deep_thing sits two bare USE FROMs away; the note citation must
        # name the declaring schema like the definition-side supertype
        # citations already do.
        expect(notes).to include("tech:Deep_arm.deep_thing,")
        expect(notes).not_to include("tech:Outer_arm.deep_thing")
      end

      it "re-qualifies attribute-tail xrefs and leaves unresolvable " \
         "ones as written" do
        notes = outer_note
        expect(notes).to include("tech:Deep_arm.deep_thing.name,")
        # nosuch_thing has no declarer anywhere in the closure: the
        # citation stays as written for the render-time gate to count.
        expect(notes).to include("tech:Outer_arm.nosuch_thing,")
      end

      it "resolves a type-named xref through the closure" do
        # middle_kind is a TYPE (not an entity) declared in Middle_arm,
        # one bare USE FROM away: the declared-element check must cover
        # every declaration kind the remarks cite.
        notes = outer_note
        expect(notes).to include("tech:Middle_arm.middle_kind,")
        expect(notes).not_to include("tech:Outer_arm.middle_kind")
      end
    end
  end
end
