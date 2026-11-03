# frozen_string_literal: true

require "json"
require "pathname"
require "tmpdir"

require "suma/delivery/pack"

# The packer contract, pinned against the Python implementation
# (scripts/srl-build/srl_pack_bundle.py + the fused iso_renamer.py /
# align_parts.py layout normalization, TCSC410303-2952): per-doc dir
# naming, section renaming, href rewriting, anchor/xref scanning,
# owned-attachment copying, and the bundle.json record.
RSpec.describe Suma::Delivery::Pack do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = Pathname.new(dir)
      write_fixtures
      example.run
    end
  end

  let(:base) { @root / "srl-build" }
  let(:repo) { @root / "corpus" }
  let(:bundle_dir) { base / "parts" / "iso-10303-99" }
  let(:bundle_json) { JSON.parse((bundle_dir / "bundle.json").read) }

  def pack(skip_layout: false)
    described_class.new(
      part: "iso-10303-99",
      srl_build_base: base,
      repo_root: repo,
      skip_layout: skip_layout,
    ).pack
  end

  def write_fixtures
    site = base / "wt" / "iso-10303-99" / "_site"
    write_plan
    write_collection_yml
    write_exp_source
    write_section_html(site, "document.xml.0.html", <<~HTML)
      <html><body>
      <p id="x_action_ISO_10303-99_2026_ISO_10303-99_2026_def">Action</p>
      <p id="zzz-lower">lower</p>
      <a href="document.xml.1.html#intro">next</a>
      <span class="unresolved-eref" data-bibitemid="express_x.action_ISO_10303-99_2026_ISO_10303-99_2026_s3" data-citeas="[ISO 10303-99]">action</span>
      </body></html>
    HTML
    write_section_html(site, "document.xml.0.err.html",
                       "<html><body></body></html>\n")
    write_section_html(site, "document.xml.1.html", <<~HTML)
      <html><body>
      <p id="x_banner_ISO_10303-99_2026_ISO_10303-99_2026_top">Banner</p>
      <a href="./document.xml.0.html">prev</a>
      <a href='document.xml.0.html#single'>single</a>
      <a href="../../plain_schemas/resources/x/x.exp">EXP</a>
      <a href="schema_docs/x/doc_x.html">doc</a>
      <span class="unresolved-eref" data-bibitemid="ISO_10303-99_ISO_10303-99_2026">ISO 10303-99</span>
      <span class="unresolved-eref" data-bibitemid="">empty</span>
      </body></html>
    HTML
    write_section_html(site, "document.xml.1.xml", "<xml/>\n")
    write_section_html(site, "document.xml.1.presentation.xml", "<xml/>\n")
    write_section_html(site, "plain_schemas/resources/x/x.exp",
                       "SCHEMA x; END_SCHEMA;\n")
    write_section_html(site, "iso10303-99_index.html", <<~HTML)
      <html><body><a href="document.xml.0.html">s0</a>
      <p id="idx_ISO_10303-99_2026_top">top</p></body></html>
    HTML
    write_section_html(site, "schema_docs/x/doc_x.html",
                       "<html><body><a href=\"document.xml.0.html\">s0</a>" \
                       "</body></html>\n")
  end

  def write(path, content)
    path.parent.mkpath
    path.write(content)
  end

  def write_plan
    write(base / "plan.json", JSON.pretty_generate(
                                "version" => 1,
                                "source_collection" => "collection-resources.yml",
                                "build_commit" => "feed1234",
                                "build_timestamp" => "2026-11-02T00:00:00Z",
                                "parts_count" => 1,
                                "parts" => [
                                  {
                                    "part_dir" => "iso-10303-99",
                                    "source_dir" => "documents/iso-10303-99",
                                    # Plan's predicted name (docid with the space kept); the packer
                                    # must use the rendered value instead.
                                    "iso_name" => "ISO_ISO 10303-99_2026",
                                    "doc_id" => "ISO 10303-99",
                                    "year" => "2026",
                                    "doc_hash" => "sha256:doc-digest",
                                    "deps_hash" => "sha256:deps-digest",
                                    "input_files" => ["documents/iso-10303-99/collection.yml"],
                                    "exp_files" => ["plain_schemas/resources/x/x.exp"],
                                  },
                                ],
                              ))
  end

  def write_collection_yml
    write(repo / "documents" / "iso-10303-99" / "collection.yml", <<~YAML)
      bibdata:
        docid:
          type: iso
          id: ISO 10303-99
        copyright:
          from: 2026
      manifest:
        docref:
        - fileref: ../../plain_schemas/resources/x/x.exp
          identifier: x
        - fileref: ../../schema_docs/x/doc_x.html
          identifier: x-doc
    YAML
  end

  def write_exp_source
    write(repo / "plain_schemas" / "resources" / "x" / "x.exp",
          "SCHEMA x; END_SCHEMA;\n")
  end

  def write_section_html(site, name, content)
    write(site / name, content)
  end

  it "creates the per-doc dir with renamed sections, leaving sources flat" do
    pack
    dir = base / "wt" / "iso-10303-99" / "_site" / "ISO_10303-99_2026"
    expect(dir.children.map { |c| c.basename.to_s }.sort).to eq(
      ["ISO_10303-99_2026_index.html",
       "ISO_10303-99_2026_section_0.err.html",
       "ISO_10303-99_2026_section_0.html",
       "ISO_10303-99_2026_section_1.html"],
    )
    site = dir.parent
    expect((site / "document.xml.1.xml").exist?).to be(true)
    expect((site / "document.xml.1.presentation.xml").exist?).to be(true)
    expect(site.children.none? do |c|
      c.basename.to_s =~ /\Adocument\.xml\.\d+\.html\z/
    end)
      .to be(true)
  end

  it "rewrites hrefs to the new section names and per-doc-relative depth" do
    pack
    dir = base / "wt" / "iso-10303-99" / "_site" / "ISO_10303-99_2026"
    section0 = (dir / "ISO_10303-99_2026_section_0.html").read
    expect(section0).to include('href="ISO_10303-99_2026_section_1.html#intro"')

    section1 = (dir / "ISO_10303-99_2026_section_1.html").read
    expect(section1).to include('href="./ISO_10303-99_2026_section_0.html"')
    expect(section1).to include("href='ISO_10303-99_2026_section_0.html#single'")
    expect(section1).to include('href="../plain_schemas/resources/x/x.exp"')
    expect(section1).to include('href="../schema_docs/x/doc_x.html"')

    index = (dir / "ISO_10303-99_2026_index.html").read
    expect(index).to include('href="ISO_10303-99_2026_section_0.html"')

    schema_doc = (dir.parent / "schema_docs/x/doc_x.html").read
    expect(schema_doc).to include('href="ISO_10303-99_2026_section_0.html"')
  end

  it "writes the bundle record with the rendered iso_name and plan hashes" do
    pack
    expect(bundle_json["version"]).to eq(1)
    expect(bundle_json["part_dir"]).to eq("iso-10303-99")
    expect(bundle_json["iso_name"]).to eq("ISO_10303-99_2026")
    expect(bundle_json["source_dir"]).to eq("documents/iso-10303-99")
    expect(bundle_json["build_commit"]).to eq("feed1234")
    expect(bundle_json["doc_id"]).to eq("ISO 10303-99")
    expect(bundle_json["year"]).to eq("2026")
    expect(bundle_json["doc_hash"]).to eq("sha256:doc-digest")
    expect(bundle_json["deps_hash"]).to eq("sha256:deps-digest")
    expect(bundle_json["input_files"])
      .to eq(["documents/iso-10303-99/collection.yml"])
    expect(bundle_json["exp_files"]).to eq(["plain_schemas/resources/x/x.exp"])
    expect(bundle_json["errors"]).to eq("build_warnings" => [])
    expect(bundle_json["build_timestamp"]).to match(/\A\d{4}-\d{2}-\d{2}T/)
  end

  it "scans anchors and unresolved-eref spans into the bundle" do
    pack
    expect(bundle_json["sections"]).to eq(
      ["ISO_10303-99_2026_index.html",
       "ISO_10303-99_2026_section_0.html",
       "ISO_10303-99_2026_section_1.html"],
    )
    expect(bundle_json["anchors"]).to eq(
      "ISO_10303-99_2026_index.html" => ["idx_ISO_10303-99_2026_top"],
      "ISO_10303-99_2026_section_0.html" => [
        "x_action_ISO_10303-99_2026_ISO_10303-99_2026_def",
        "zzz-lower",
      ],
      "ISO_10303-99_2026_section_1.html" => [
        "x_banner_ISO_10303-99_2026_ISO_10303-99_2026_top",
      ],
    )
    expect(bundle_json["unresolved_xrefs"]).to eq(
      [
        {
          "source_file" => "ISO_10303-99_2026_section_0.html",
          "bibitemid" => "express_x.action_ISO_10303-99_2026_ISO_10303-99_2026_s3",
          "schema_ref" => "x",
          "entity_ref" => "action",
          "display_text" => "action",
          "citeas" => "[ISO 10303-99]",
        },
        {
          "source_file" => "ISO_10303-99_2026_section_1.html",
          "bibitemid" => "ISO_10303-99_ISO_10303-99_2026",
          "schema_ref" => nil,
          "entity_ref" => nil,
          "display_text" => "ISO 10303-99",
          "citeas" => "",
        },
      ],
    )
  end

  it "copies the per-doc dir, owned schema_docs, and plain_schemas" do
    pack
    site = bundle_dir / "site"
    expect((site / "ISO_10303-99_2026" / "ISO_10303-99_2026_section_0.html").exist?)
      .to be(true)
    expect((site / "schema_docs" / "x" / "doc_x.html").exist?).to be(true)
    expect((site / "plain_schemas" / "resources" / "x" / "x.exp").exist?).to be(true)
    expect(bundle_json["schema_docs"]).to eq(["x"])
    expect(bundle_json["plain_schemas"]).to eq(["resources/x/x.exp"])
    expect((bundle_dir / "logs").directory?).to be(true)
  end

  it "is idempotent: a second run skips normalization and saves the prior bundle" do
    pack
    first = File.read(bundle_dir / "bundle.json")
    site_html = base / "wt" / "iso-10303-99" / "_site" / "ISO_10303-99_2026"
    before = site_html.children.map { |c| c.basename.to_s }.sort

    pack

    expect(site_html.children.map { |c| c.basename.to_s }.sort).to eq(before)
    previous = JSON.parse(File.read(bundle_dir / "bundle.json.previous"))
    expect(previous).to eq(JSON.parse(first))
    second = File.read(bundle_dir / "bundle.json")
    expect(second.sub(/"build_timestamp": "[^"]+"/, "TS"))
      .to eq(first.sub(/"build_timestamp": "[^"]+"/, "TS"))
  end

  it "skips normalization on demand via skip_layout" do
    pack
    section = base / "wt" / "iso-10303-99" / "_site" / "ISO_10303-99_2026" /
      "ISO_10303-99_2026_section_0.html"
    content = section.read

    described_class.new(
      part: "iso-10303-99", srl_build_base: base, repo_root: repo,
      skip_layout: true
    ).pack

    expect(section.read).to eq(content)
  end

  it "raises when the part is missing from the plan" do
    expect do
      described_class.new(
        part: "iso-10303-404", srl_build_base: base, repo_root: repo,
      ).pack
    end.to raise_error(/Part 'iso-10303-404' not in plan/)
  end

  it "matches the pinned bundle.json byte-for-byte" do
    pack
    actual = File.read(bundle_dir / "bundle.json")
    timestamp = actual[/\A.*?"build_timestamp": "([^"]+)"/m, 1]
    expect(actual).to eq(golden_bundle(timestamp))
  end

  def golden_bundle(timestamp)
    text = <<~JSON
      {
        "version": 1,
        "part_dir": "iso-10303-99",
        "iso_name": "ISO_10303-99_2026",
        "source_dir": "documents/iso-10303-99",
        "build_timestamp": "#{timestamp}",
        "build_commit": "feed1234",
        "doc_id": "ISO 10303-99",
        "year": "2026",
        "doc_hash": "sha256:doc-digest",
        "deps_hash": "sha256:deps-digest",
        "input_files": [
          "documents/iso-10303-99/collection.yml"
        ],
        "exp_files": [
          "plain_schemas/resources/x/x.exp"
        ],
        "sections": [
          "ISO_10303-99_2026_index.html",
          "ISO_10303-99_2026_section_0.html",
          "ISO_10303-99_2026_section_1.html"
        ],
        "schema_docs": [
          "x"
        ],
        "plain_schemas": [
          "resources/x/x.exp"
        ],
        "anchors": {
          "ISO_10303-99_2026_index.html": [
            "idx_ISO_10303-99_2026_top"
          ],
          "ISO_10303-99_2026_section_0.html": [
            "x_action_ISO_10303-99_2026_ISO_10303-99_2026_def",
            "zzz-lower"
          ],
          "ISO_10303-99_2026_section_1.html": [
            "x_banner_ISO_10303-99_2026_ISO_10303-99_2026_top"
          ]
        },
        "unresolved_xrefs": [
          {
            "source_file": "ISO_10303-99_2026_section_0.html",
            "bibitemid": "express_x.action_ISO_10303-99_2026_ISO_10303-99_2026_s3",
            "schema_ref": "x",
            "entity_ref": "action",
            "display_text": "action",
            "citeas": "[ISO 10303-99]"
          },
          {
            "source_file": "ISO_10303-99_2026_section_1.html",
            "bibitemid": "ISO_10303-99_ISO_10303-99_2026",
            "schema_ref": null,
            "entity_ref": null,
            "display_text": "ISO 10303-99",
            "citeas": ""
          }
        ],
        "errors": {
          "build_warnings": []
        }
      }
    JSON
    # The Python packer writes json.dumps output with no trailing
    # newline; the port matches it byte-for-byte.
    text.chomp
  end
end
