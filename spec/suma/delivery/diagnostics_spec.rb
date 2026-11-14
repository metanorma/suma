# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

# The err.html census (metanorma/suma#203): rows grouped by the stable
# identity of a diagnostic row — category + rule — not the code string,
# which migrates across metanorma releases (iso-10303#859: rows the
# part2 gate grepped as STANDOC_38 were re-emitted as ISO_56, so the
# gate read 0 over 476 live rows). The fixture pins the exact structure
# Metanorma::Utils::Log#write emits (as observed in the iso-10303
# documents/iso-10303-2/document.err.html): one <h2> per category, each
# followed by a table whose data rows are six cells — Line, ID, Error
# (the rule code), Message, Context, Severity — with the ID cell
# rendering as a `th`. Style carries one rule twice plus another rule
# once; Referencing carries the migrated broken-xref rule once.
RSpec.describe Suma::Delivery::Diagnostics do
  let(:fixture_path) do
    File.expand_path("../fixtures/diagnostics/document.err.html", __dir__)
  end
  let(:fixture_html) { File.read(fixture_path) }
  let(:census) do
    {
      "Style" => { "STANDOC_48" => 2, "ISO_45" => 1 },
      "Referencing" => { "ISO_56" => 1 },
    }
  end

  describe ".count" do
    it "groups rows by category and rule from HTML text" do
      expect(described_class.count(fixture_html).to_h).to eq(census)
    end

    it "reads an err.html file path" do
      expect(described_class.count(fixture_path).to_h).to eq(census)
    end

    it "counts an error-report with no rows as empty" do
      # The shape a clean document writes (iso-10303
      # collection-output.err.html): the header and an empty index.
      empty = "<html><body><h1>errors</h1><ul></ul></body></html>"

      expect(described_class.count(empty).to_h).to eq({})
    end
  end

  describe Suma::Delivery::Diagnostics::Counts do
    let(:counts) { described_class.new(census) }

    def extra_counts
      described_class.new("Style" => { "STANDOC_48" => 1 },
                          "Terms" => { "STANDOC_27" => 2 })
    end

    def merged_census
      { "Style" => { "STANDOC_48" => 3, "ISO_45" => 1 },
        "Referencing" => { "ISO_56" => 1 },
        "Terms" => { "STANDOC_27" => 2 } }
    end

    it "enumerates category/rule/count triples" do
      expect(counts.to_a).to contain_exactly(
        ["Style", "STANDOC_48", 2],
        ["Style", "ISO_45", 1],
        ["Referencing", "ISO_56", 1],
      )
    end

    it "totals per category, zero for an unreported one" do
      aggregate_failures do
        expect(counts.total("Style")).to eq(3)
        expect(counts.total("Referencing")).to eq(1)
        expect(counts.total("Terms")).to eq(0)
      end
    end

    it "counts single rules, zero for an unreported one" do
      aggregate_failures do
        expect(counts.rule_count("Style", "STANDOC_48")).to eq(2)
        expect(counts.rule_count("Style", "ISO_56")).to eq(0)
      end
    end

    it "counts rows overall" do
      expect(counts.rows).to eq(4)
    end

    it "merges censuses by summing shared categories and rules" do
      expect(counts.merge(extra_counts).to_h).to eq(merged_census)
    end
  end

  describe ".count_site" do
    let(:site) { Dir.mktmpdir }
    let(:summed) do
      { "Style" => { "STANDOC_48" => 4, "ISO_45" => 2 },
        "Referencing" => { "ISO_56" => 2 } }
    end

    after { FileUtils.rm_rf(site) }

    # One report in the site root, one nested, one page that is not an
    # error report at all.
    def populate_site(dir)
      File.write(File.join(dir, "a.err.html"), fixture_html)
      FileUtils.mkdir_p(File.join(dir, "documents", "part2"))
      File.write(File.join(dir, "documents", "part2", "document.err.html"),
                 fixture_html)
      File.write(File.join(dir, "plain.html"),
                 "<html><body>not an error report</body></html>")
    end

    it "sums the census of every err.html under the site" do
      populate_site(site)

      expect(described_class.count_site(site).to_h).to eq(summed)
    end

    it "sums to zero over a site without error reports" do
      expect(described_class.count_site(site).to_h).to eq({})
    end
  end
end
