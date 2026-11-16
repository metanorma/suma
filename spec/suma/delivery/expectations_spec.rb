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

  # diagnostics_max: category => rule => cap over the report's err.html
  # census. The stable row identity is category + rule; codes migrate
  # (iso-10303#859), so the gate keys on both.
  describe "diagnostics_max" do
    let(:report_with_diagnostics) do
      { **report, "diagnostics" => { "Referencing" => { "ISO_56" => 3 } } }
    end

    it "passes when no rule exceeds its cap" do
      e = expectations(diagnostics_max:
                         { "Referencing" => { "ISO_56" => 3 },
                           "Style" => { "STANDOC_48" => 0 } })

      expect(e.violations(report_with_diagnostics, [])).to be_empty
    end

    it "counts a rule absent from the census as zero rows" do
      e = expectations(diagnostics_max:
                         { "Referencing" => { "ISO_56" => 0 } })

      expect(e.violations(report, [])).to be_empty
    end

    it "flags every rule over its cap" do
      e = expectations(diagnostics_max:
                         { "Referencing" => { "ISO_56" => 2 },
                           "Style" => { "ISO_45" => 0 } })
      failures = e.violations(
        { **report_with_diagnostics,
          "diagnostics" => { "Referencing" => { "ISO_56" => 3 },
                             "Style" => { "ISO_45" => 1 } } },
        [],
      )

      expect(failures).to contain_exactly(
        "Referencing/ISO_56: got 3, expected at most 2",
        "Style/ISO_45: got 1, expected at most 0",
      )
    end

    it "round-trips the nested manifest through YAML" do
      yaml = <<~YAML
        diagnostics_max:
          Referencing:
            ISO_56: 0
      YAML
      e = described_class.from_yaml(yaml)

      expect(e.diagnostics_max).to eq("Referencing" => { "ISO_56" => 0 })
      expect(e.violations({ **report,
                            "diagnostics" =>
                              { "Referencing" => { "ISO_56" => 1 } } }, []))
        .to eq(["Referencing/ISO_56: got 1, expected at most 0"])
    end
  end

  # Page-shape maxima over the verifier's census (TRThurman,
  # iso-10303#857): build-directory paths, incomplete listings,
  # unpublished schema remarks, asciidoc leaks.
  describe "page-shape maxima" do
    let(:shaped_report) do
      { **report,
        "build_dir_pages" => %w[p.html q.html],
        "build_dir_occurrences" => 4,
        "incomplete_listings" => %w[doc_a.html],
        "missing_schema_remarks" => %w[b_schema c_schema],
        "asciidoc_leak_pages" => %w[p.html],
        "asciidoc_leak_occurrences" => 16 }
    end

    it "flags every census over its cap in one pass" do
      e = expectations(build_dir_references_max: 3,
                       incomplete_listings_max: 0,
                       missing_schema_remarks_max: 1,
                       asciidoc_leaks_max: 15)

      expect(e.violations(shaped_report, [])).to contain_exactly(
        "build_dir_references_max: got 4, expected at most 3",
        "incomplete_listings_max: got 1, expected at most 0",
        "missing_schema_remarks_max: got 2, expected at most 1",
        "asciidoc_leaks_max: got 16, expected at most 15",
      )
    end

    it "passes a census at or under every cap" do
      e = expectations(build_dir_references_max: 4,
                       incomplete_listings_max: 1,
                       missing_schema_remarks_max: 2,
                       asciidoc_leaks_max: 16)

      expect(e.violations(shaped_report, [])).to be_empty
    end

    it "defaults the page-shape maxima to zero tolerance" do
      expect(expectations.violations(shaped_report, [])).to contain_exactly(
        "build_dir_references_max: got 4, expected at most 0",
        "incomplete_listings_max: got 1, expected at most 0",
        "missing_schema_remarks_max: got 2, expected at most 0",
        "asciidoc_leaks_max: got 16, expected at most 0",
      )
    end

    it "round-trips the prefixes and maxima through YAML" do
      yaml = <<~YAML
        forbidden_path_prefixes:
        - /export/
        - /scratch/
        build_dir_references_max: 5
        incomplete_listings_max: 43
        missing_schema_remarks_max: 3
        asciidoc_leaks_max: 16
      YAML
      e = described_class.from_yaml(yaml)

      expect(e.forbidden_path_prefixes).to eq(["/export/", "/scratch/"])
      expect(e.build_dir_references_max).to eq(5)
      expect(e.incomplete_listings_max).to eq(43)
      expect(e.missing_schema_remarks_max).to eq(3)
      expect(e.asciidoc_leaks_max).to eq(16)
    end

    it "reads page-shape keys absent from a sparse report as zero" do
      e = expectations

      expect(e.violations(report, [])).to be_empty
    end
  end
end
