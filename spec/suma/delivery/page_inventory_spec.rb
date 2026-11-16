# frozen_string_literal: true

require "spec_helper"
require "suma/delivery/page_inventory"

# The per-page inventory ratchet: baseline loading from flat YAML and
# the page-for-page comparison that surfaces rendering drift.
RSpec.describe Suma::Delivery::PageInventory do
  describe ".load_baseline" do
    it "reads the flat page => counts format" do
      yaml = <<~YAML
        schema_docs/doc_a.html:
          imgs: 12
          links: 40
        ISO_X/ISO_X_index.html:
          imgs: 0
          links: 7
      YAML

      expect(described_class.load_baseline(yaml)).to eq(
        "schema_docs/doc_a.html" => { "imgs" => 12, "links" => 40 },
        "ISO_X/ISO_X_index.html" => { "imgs" => 0, "links" => 7 },
      )
    end

    it "rejects a non-mapping baseline" do
      expect { described_class.load_baseline("- a\n- b\n") }
        .to raise_error(ArgumentError, /must be a YAML mapping/)
    end

    it "coerces counts to integers and tolerates null pages" do
      yaml = <<~YAML
        p.html:
          imgs: "3"
          links:
      YAML

      expect(described_class.load_baseline(yaml))
        .to eq("p.html" => { "imgs" => 3, "links" => 0 })
    end
  end

  describe ".changes" do
    it "is empty when every page matches the baseline" do
      current = { "a.html" => { "imgs" => 1, "links" => 2 } }

      expect(described_class.changes(current, current)).to be_empty
    end

    it "surfaces every moved count as [baseline, current] pairs" do
      changes = described_class.changes(
        { "a.html" => { "imgs" => 0, "links" => 9 },
          "b.html" => { "imgs" => 2, "links" => 0 },
          "new.html" => { "imgs" => 1, "links" => 1 } },
        { "a.html" => { "imgs" => 1, "links" => 9 },
          "b.html" => { "imgs" => 2, "links" => 3 },
          "gone.html" => { "imgs" => 4, "links" => 4 } },
      )

      expect(changes).to eq(
        "a.html" => { "imgs" => [1, 0] },
        "b.html" => { "links" => [3, 0] },
        "gone.html" => { "imgs" => [4, 0], "links" => [4, 0] },
        "new.html" => { "imgs" => [0, 1], "links" => [0, 1] },
      )
    end
  end
end
