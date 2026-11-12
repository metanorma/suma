# frozen_string_literal: true

require "spec_helper"
require "suma/delivery/expectations"

# The corpus-side gate thresholds: violations surface every broken
# condition in one pass, unset checks stay silent, and the maxima
# default to zero tolerance.
RSpec.describe Suma::Delivery::Expectations do
  def expectations(**attrs)
    described_class.new(**attrs)
  end

  let(:report) do
    { "inventory" => { "sections" => 650, "index_pages" => 43,
                       "schema_attachments" => 120, "schema_docs" => 101 },
      "missing_express_pages" => [] }
  end
  let(:broken_links) { [] }

  it "passes a site that meets every threshold" do
    e = expectations(sections_min: 650, index_pages: 43,
                     schema_attachments_min: 100, schema_docs_min: 101)

    expect(e.violations(report, broken_links)).to be_empty
  end

  it "treats a bare threshold (index_pages) as exact" do
    e = expectations(index_pages: 43)

    failures = e.violations(
      { **report,
        "inventory" => { **report["inventory"], "index_pages" => 44 } }, []
    )

    expect(failures).to eq(["index_pages: got 44, expected exactly 43"])
  end

  it "flags every shortfall, minima and maxima in one pass" do
    e = expectations(sections_min: 700, index_pages: 40,
                     schema_attachments_min: 130, schema_docs_min: 110,
                     missing_express_max: 0, broken_links_max: 2)

    failures = e.violations({ **report, "missing_express_pages" => %w[a b] },
                            %w[l1 l2 l3])

    expect(failures).to contain_exactly(
      "sections_min: got 650, expected at least 700",
      "index_pages: got 43, expected exactly 40",
      "schema_attachments_min: got 120, expected at least 130",
      "schema_docs_min: got 101, expected at least 110",
      "missing_express_max: got 2, expected at most 0",
      "broken_links_max: got 3, expected at most 2",
    )
  end

  it "leaves unset checks silent" do
    expect(expectations.violations(
             { "sections" => 0, "index_pages" => 0,
               "schema_attachments" => 0, "schema_docs" => 0,
               "missing_express_pages" => [] },
             [],
           )).to be_empty
  end

  it "round-trips through YAML" do
    yaml = <<~YAML
      sections_min: 650
      index_pages: 43
      schema_attachments_min: 100
      schema_docs_min: 100
    YAML
    e = described_class.from_yaml(yaml)

    expect(e.sections_min).to eq(650)
    expect(e.index_pages).to eq(43)
    expect(e.missing_express_max).to eq(0)
  end
end
