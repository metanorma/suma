# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"

# The stitcher contract, pinned against the Python implementation
# (scripts/suma2srl/srl_stitch.py, TCSC410303-2952): registry resolution of
# the three bibitemid shapes, span rewriting, synthesized index, audit
# records, and the inject invariants.
RSpec.describe Suma::Srl::Stitcher do
  def write(path, content)
    path.parent.mkpath
    path.write(content)
  end

  let(:anchor_b) do
    "representation_schema.representation_ISO_10303-43_2025_ISO_10303-43_2025_scope"
  end

  def build_fixtures(root)
    write(root / "plan.json", JSON.pretty_generate(
                                "build_commit" => "abc1234",
                                "parts" => [
                                  { "part_dir" => "iso-10303-41",
                                    "doc_id" => "10303-41" },
                                  { "part_dir" => "iso-10303-43",
                                    "doc_id" => "10303-43" },
                                ],
                              ))

    write(root / "bundles/iso-10303-41/bundle.json", JSON.pretty_generate(
                                                       "iso_name" => "ISO_10303-41_2025",
                                                       "anchors" => {
                                                         "ISO_10303-41_2025_section_0.html" =>
                                                           ["action_schema_action_ISO_10303-41_2025_ISO_10303-41_2025_x"],
                                                       },
                                                       "unresolved_xrefs" => [
                                                         { "bibitemid" => "express_representation_schema.representation_ISO_10303-43_2025" },
                                                       ],
                                                     ))
    write(root / "bundles/iso-10303-41/site/ISO_10303-41_2025/" \
                 "ISO_10303-41_2025_section_0.html",
          <<~HTML)
            <html><body>
            <p><span class="unresolved-eref" data-bibitemid="express_representation_schema.representation_ISO_10303-43_2025">Representation</span></p>
            <p><span class="unresolved-eref" data-bibitemid="express_unknown_entity_ISO_10303-99_2025">Unknown</span></p>
            <p><span class="unresolved-eref" data-bibitemid="action_schema.exp_ISO_10303-41_2025">the EXPRESS listing</span></p>
            </body></html>
          HTML
    write(root / "bundles/iso-10303-41/site/plain_schemas/resources/" \
                 "action_schema/action_schema.exp", "SCHEMA action_schema; END_SCHEME;")

    write(root / "bundles/iso-10303-43/bundle.json", JSON.pretty_generate(
                                                       "iso_name" => "ISO_10303-43_2025",
                                                       "anchors" => { "ISO_10303-43_2025_section_1.html" => [anchor_b] },
                                                       "unresolved_xrefs" => [],
                                                     ))
    write(root / "bundles/iso-10303-43/site/ISO_10303-43_2025/" \
                 "ISO_10303-43_2025_section_1.html",
          <<~HTML)
            <html><body>
            <p><span class="unresolved-eref" data-bibitemid="ISO_10303-41_ISO_10303-41_2025">ISO 10303-41</span></p>
            </body></html>
          HTML
  end

  def stitch(root, out)
    described_class.new(
      bundles_dir: root / "bundles",
      plan_path: root / "plan.json",
      out_dir: out,
    ).stitch
  end

  it "resolves the three bibitemid shapes and records the unresolvable one" do
    Dir.mktmpdir do |dir|
      root = Pathname.new(dir)
      out = root / "merged" / "_site"
      build_fixtures(root)

      result = stitch(root, out)

      expect(result.resolved).to eq(3)
      expect(result.broken).to eq(1)

      a_html = (out / "ISO_10303-41_2025/ISO_10303-41_2025_section_0.html").read
      expected_a = '<a href="../ISO_10303-43_2025/ISO_10303-43_2025_section_1.html#' \
        "#{anchor_b}\" class=\"resolved-eref\">Representation</a>"
      expect(a_html).to include(expected_a)
      expect(a_html).to include(
        '<a href="../plain_schemas/resources/action_schema/action_schema.exp" ' \
        'class="resolved-eref">the EXPRESS listing</a>',
      )
      expect(a_html).to include("Unknown</span>")

      b_html = (out / "ISO_10303-43_2025/ISO_10303-43_2025_section_1.html").read
      expect(b_html).to include(
        '<a href="../ISO_10303-41_2025/ISO_10303-41_2025_index.html" ' \
        'class="resolved-eref">ISO 10303-41</a>',
      )
    end
  end

  it "writes the broken-xref audit record" do
    Dir.mktmpdir do |dir|
      root = Pathname.new(dir)
      out = root / "merged" / "_site"
      build_fixtures(root)
      stitch(root, out)

      broken = JSON.parse((out / "broken_xrefs.json").read)
      expect(broken["count"]).to eq(1)
      expect(broken["entries"].first["bibitemid"])
        .to eq("express_unknown_entity_ISO_10303-99_2025")
    end
  end

  it "synthesizes the top-level index and the stitch summary" do
    Dir.mktmpdir do |dir|
      root = Pathname.new(dir)
      out = root / "merged" / "_site"
      build_fixtures(root)
      stitch(root, out)

      index = (out / "index.html").read
      expect(index).to include("STEP Resources Library")
      expect(index).to include("ISO_10303-41_2025/ISO_10303-41_2025_index.html")
      expect(index).to include("ISO_10303-43_2025/ISO_10303-43_2025_index.html")

      summary = JSON.parse((out / "stitch_summary.json").read)
      expect(summary["parts_stitched"])
        .to eq(["iso-10303-41", "iso-10303-43"])
      expect(summary["anchor_registry_size"]).to eq(2)
      expect(summary["doc_registry_size"]).to eq(2)
      expect(summary["xrefs_resolved"]).to eq(3)
      expect(summary["xrefs_broken"]).to eq(1)
      expect(summary["build_commit"]).to eq("abc1234")
    end
  end

  describe "inject invariants" do
    it "rejects an iso_name change against the previous bundle" do
      Dir.mktmpdir do |dir|
        root = Pathname.new(dir)
        build_fixtures(root)
        write(root / "bundles/iso-10303-41/bundle.json.previous",
              JSON.pretty_generate("iso_name" => "ISO_10303-41_2019"))
        write(root / "bundles/iso-10303-43/bundle.json.previous",
              JSON.pretty_generate("iso_name" => "ISO_10303-43_2025"))

        stitcher = described_class.new(
          bundles_dir: root / "bundles",
          plan_path: root / "plan.json",
          out_dir: root / "merged" / "_site",
          inject: "iso-10303-41",
        )
        expect { stitcher.stitch }
          .to raise_error(/iso_name changed from "ISO_10303-41_2019"/)
      end
    end

    it "rejects a rebuild that drops scopes consumed by other parts" do
      Dir.mktmpdir do |dir|
        root = Pathname.new(dir)
        build_fixtures(root)
        # The previous bundle exposed the representation scope that
        # iso-10303-41's unresolved_xrefs consume; the new bundle does not.
        write(root / "bundles/iso-10303-43/bundle.json.previous",
              JSON.pretty_generate(
                "iso_name" => "ISO_10303-43_2025",
                "anchors" => {
                  "ISO_10303-43_2025_section_1.html" => [anchor_b],
                },
              ))
        write(root / "bundles/iso-10303-43/bundle.json",
              JSON.pretty_generate(
                "iso_name" => "ISO_10303-43_2025",
                "anchors" => { "ISO_10303-43_2025_section_1.html" => [] },
                "unresolved_xrefs" => [],
              ))

        stitcher = described_class.new(
          bundles_dir: root / "bundles",
          plan_path: root / "plan.json",
          out_dir: root / "merged" / "_site",
          inject: "iso-10303-43",
        )
        expect { stitcher.stitch }
          .to raise_error(/anchor regression.*representation_schema\.representation/)
      end
    end
  end
end
