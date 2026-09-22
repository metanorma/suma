# frozen_string_literal: true

require "spec_helper"

RSpec.describe Suma::SchemaTemplate::Document do
  let(:schema_id) { "description_assignment_mim" }
  let(:rendered) { described_class.new(schema_id).render("schemas.yaml") }

  it "renders the full schema with live cross-reference links" do
    aggregate_failures do
      expect(rendered).to include("{{ schema.formatted_hyperlinked_adoc }}")
      # +macros lets Asciidoctor expand the <<schema.item,item>> xref
      # macros the hyperlinked face emits inside the source block
      expect(rendered).to include('[source%unnumbered,subs="+macros"]')
    end
  end

  it "keeps the element anchors the links point at" do
    aggregate_failures do
      expect(rendered).to include("[[#{schema_id}.constants]]")
      expect(rendered).to include("[[#{schema_id}.{{thing.id")
    end
  end

  it "emits only XML" do
    expect(described_class::EXTENSIONS).to eq("xml")
  end
end
