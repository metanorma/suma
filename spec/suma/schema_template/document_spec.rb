# frozen_string_literal: true

require "spec_helper"

RSpec.describe Suma::SchemaTemplate::Document do
  let(:schema_id) { "description_assignment_mim" }
  let(:rendered) { described_class.new(schema_id).render("schemas.yaml") }

  it "renders the full schema through the hyperlinked listing block" do
    expect(rendered)
      .to include("{{ schema.formatted_hyperlinked_adoc_listing }}")
  end

  it "adds no source fence of its own" do
    # the listing method emits the [source%unnumbered,subs="+macros"]
    # block with its own fence — the template adds none
    aggregate_failures do
      expect(rendered).not_to include('[source%unnumbered,subs="+macros"]')
      expect(rendered).not_to include("\n--\n")
    end
  end

  it "keeps the element anchors the links point at" do
    aggregate_failures do
      expect(rendered).to include("[[{{ schema.id")
      expect(rendered).to include(".constants]]")
      expect(rendered).to include(".{{thing.id")
    end
  end

  it "emits only XML" do
    expect(described_class::EXTENSIONS).to eq("xml")
  end
end
