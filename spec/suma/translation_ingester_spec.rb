# frozen_string_literal: true

require "suma"
require "glossarist"
require "tmpdir"

RSpec.describe Suma::TranslationIngester do
  let(:manifest) do
    File.expand_path("../fixtures/owl/schemas.yaml", __dir__)
  end
  let(:urn_base) { "urn:example:t5" }
  let(:work_dir) { Dir.mktmpdir("suma_translations") }
  let(:concepts_dir) { File.join(work_dir, "concepts") }
  let(:translations_file) { File.join(work_dir, "translations.yaml") }

  before do
    Suma::TermExtractor.new(
      manifest, concepts_dir, urn: urn_base, language_codes: %w[fra deu]
    ).call
  end

  after { FileUtils.rm_rf(work_dir) }

  def concept_document(concept_id, dir: concepts_dir)
    file = Dir[File.join(dir, "*.yaml")].find do |path|
      doc = Glossarist::V3::ConceptDocument.from_yamls(File.read(path))
      doc.concept.data.id == concept_id
    end
    Glossarist::V3::ConceptDocument.from_yamls(File.read(file))
  end

  def localization(document, language)
    document.localizations.find do |l10n|
      l10n.data.language_code == language
    end
  end

  def designation(document, language)
    localization(document, language).data.terms.first.designation
  end

  def definition_content(document, language)
    localization(document, language).data.definition.first.content
  end

  # The persisted localization "id" (Glossarist parses it as #id).
  def persisted_id(concept_id, language)
    file = Dir[File.join(concepts_dir, "*.yaml")].find do |path|
      Glossarist::V3::ConceptDocument.from_yamls(File.read(path))
        .concept.data.id == concept_id
    end
    YAML.load_stream(File.read(file))
      .find { |doc| doc.dig("data", "language_code") == language }["id"]
  end

  def term_entry(designation)
    { "designation" => designation, "type" => "expression",
      "normative_status" => "preferred" }
  end

  def write_translations(entries)
    File.write(translations_file, YAML.dump(entries))
  end

  def ingest
    described_class.new(
      concepts_dir: concepts_dir, translations: translations_file,
    ).ingest
  end

  it "replaces the fields a translation provides" do
    persisted_before = persisted_id("example_schema.part", "fra")
    write_translations([{
                         "concept_id" => "example_schema.part",
                         "data" => {
                           "language_code" => "fra",
                           "terms" => [term_entry("pièce")],
                         },
                       }])

    ingest

    document = concept_document("example_schema.part")
    aggregate_failures do
      expect(designation(document, "fra")).to eq("pièce")
      expect(definition_content(document, "fra"))
        .to include("entity data type")
      expect(document.concept.data.localized_concepts.keys)
        .to contain_exactly("eng", "fra", "deu")
      expect(persisted_id("example_schema.part", "fra"))
        .to eq(persisted_before)
    end
  end

  it "falls back to the source language for omitted fields" do
    write_translations([{
                         "concept_id" => "example_schema.part",
                         "data" => {
                           "language_code" => "deu",
                           "terms" => [term_entry("Teil")],
                         },
                       }])

    ingest

    document = concept_document("example_schema.part")
    aggregate_failures do
      expect(designation(document, "deu")).to eq("Teil")
      expect(definition_content(document, "deu"))
        .to eq(definition_content(document, "eng"))
    end
  end

  it "creates a language absent from the extracted concepts" do
    write_translations([{
                         "concept_id" => "example_schema.part",
                         "data" => {
                           "language_code" => "zho",
                           "terms" => [term_entry("零件")],
                         },
                       }])

    ingest

    document = concept_document("example_schema.part")
    expected_uuid = Glossarist::Utilities::UUID.uuid_v5(
      Glossarist::Utilities::UUID::OID_NAMESPACE,
      "example_schema.part-zho",
    )

    aggregate_failures do
      expect(designation(document, "zho")).to eq("零件")
      expect(definition_content(document, "zho"))
        .to eq(definition_content(document, "eng"))
      expect(persisted_id("example_schema.part", "zho")).to eq(expected_uuid)
      expect(document.concept.data.localized_concepts["zho"])
        .to eq(expected_uuid)
    end
  end

  it "matches a translation by localized uuid" do
    write_translations([{
                         "id" => concept_document("example_schema.part")
                           .concept.data.localized_concepts["fra"],
                         "data" => {
                           "language_code" => "fra",
                           "terms" => [term_entry("pièce")],
                         },
                       }])

    ingest

    expect(designation(concept_document("example_schema.part"), "fra"))
      .to eq("pièce")
  end

  it "round-trips the updated document through ConceptDocument" do
    write_translations([{
                         "concept_id" => "example_schema.part",
                         "data" => {
                           "language_code" => "fra",
                           "terms" => [term_entry("pièce")],
                           "definition" =>
                             [{ "content" => "Pièce d'un assemblage." }],
                         },
                       }])

    ingest

    document = concept_document("example_schema.part")
    aggregate_failures do
      expect(designation(document, "fra")).to eq("pièce")
      expect(definition_content(document, "fra"))
        .to eq("Pièce d'un assemblage.")
      expect(document.concept.data.localized_concepts.keys)
        .to contain_exactly("eng", "fra", "deu")
    end
  end

  it "updates the concepts in place and can write elsewhere" do
    write_translations([{
                         "concept_id" => "example_schema.part",
                         "data" => {
                           "language_code" => "fra",
                           "terms" => [term_entry("pièce")],
                         },
                       }])
    output_dir = File.join(work_dir, "translated")

    described_class.new(
      concepts_dir: concepts_dir, translations: translations_file,
      output_dir: output_dir
    ).ingest

    aggregate_failures do
      expect(designation(concept_document("example_schema.part"), "fra"))
        .not_to eq("pièce")
      expect(designation(concept_document("example_schema.part",
                                          dir: output_dir), "fra"))
        .to eq("pièce")
    end
  end

  it "rejects entries that match no concept" do
    write_translations([{
                         "concept_id" => "example_schema.nope",
                         "data" => { "language_code" => "fra" },
                       }])

    expect { ingest }
      .to raise_error(Suma::Error, /unmatched translation entries/)
  end
end
