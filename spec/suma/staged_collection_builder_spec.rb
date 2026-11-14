# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "stringio"
require "yaml"
require "fileutils"

# Unit coverage for the pure, no-compile logic of the staged builder: extracting
# document members from a (possibly nested) collection manifest in order,
# excluding attachments, and constructing the isolated single-member and
# reinflation manifests. The end-to-end staged compile is exercised separately
# (it requires the metanorma preserve/store/reinflate engine).
RSpec.describe Suma::StagedCollectionBuilder do
  def builder_for(manifest, **opts)
    dir = Dir.mktmpdir
    path = File.join(dir, "collection-output.yaml")
    File.write(path, manifest.to_yaml)
    described_class.new(collection_config_path: path,
                        output_directory: File.join(dir, "_site"), **opts)
  end

  subject(:builder) { builder_for(manifest) }

  let(:manifest) do
    {
      "directives" => ["documents-inline"],
      "bibdata" => { "title" => "Coll", "type" => "collection" },
      "manifest" => {
        "level" => "collection",
        "manifest" => [
          { "level" => "subcollection", "title" => "Standards",
            "docref" => [
              { "fileref" => "a.xml", "identifier" => "ISO 1", "sectionsplit" => true },
              { "fileref" => "b.xml", "identifier" => "ISO 2" },
            ] },
          { "level" => "subcollection", "title" => "Amendments",
            "docref" => { "fileref" => "c.xml", "identifier" => "ISO 3" } },
          { "level" => "attachments", "title" => "Attachments",
            "docref" => [
              { "fileref" => "logo.svg", "identifier" => "logo.svg", "attachment" => true },
            ] },
        ],
      },
    }
  end

  describe "#collection_members" do
    let(:members) { builder.send(:collection_members) }

    it "extracts every document member in manifest order" do
      expect(members.map { |m| m["identifier"] }).to eq(["ISO 1", "ISO 2", "ISO 3"])
    end

    it "excludes attachments" do
      expect(members.map { |m| m["fileref"] }).not_to include("logo.svg")
    end

    it "carries the sectionsplit flag through" do
      expect(members.first["sectionsplit"]).to be true
      expect(members[1]).not_to have_key("sectionsplit")
    end

    it "handles both a docref array and a single docref hash" do
      expect(members.map { |m| m["fileref"] }).to eq(["a.xml", "b.xml", "c.xml"])
    end
  end

  describe "#single_member_manifest" do
    let(:one) { builder.send(:single_member_manifest, "fileref" => "a.xml", "identifier" => "ISO 1") }

    it "reuses the collection directives and bibdata" do
      expect(one["directives"]).to eq(["documents-inline"])
      expect(one["bibdata"]).to eq("title" => "Coll", "type" => "collection")
    end

    it "contains exactly the one member" do
      docrefs = one["manifest"]["manifest"].first["docref"]
      expect(docrefs).to eq([{ "fileref" => "a.xml", "identifier" => "ISO 1" }])
    end
  end

  describe "#slug" do
    it "matches the metanorma ArtifactStore filesystem-safe slug" do
      expect(builder.send(:slug, "ISO 17301-1:2016/Amd.1:2017"))
        .to eq("ISO-17301-1-2016-Amd.1-2017")
    end
  end

  describe "#shard_members" do
    let(:members) { builder.send(:collection_members) }

    def shard_ids(shard)
      picked = builder_for(manifest, shard: shard)
        .send(:shard_members, members)
      picked.map { |m| m["identifier"] }
    end

    it "keeps every member when no shard is given" do
      expect(builder.send(:shard_members, members)).to eq(members)
    end

    it "selects the members matching index % total, in order" do
      expect(shard_ids([0, 2])).to eq(["ISO 1", "ISO 3"])
      expect(shard_ids([1, 2])).to eq(["ISO 2"])
    end

    it "partitions the members across all shards of a total" do
      picked = (0...3).flat_map do |i|
        builder_for(manifest, shard: [i, 3]).send(:shard_members, members)
      end
      expect(picked).to eq(members)
    end
  end

  describe "#isolate_members" do
    let(:members) { builder.send(:collection_members) }

    it "stages exactly the member whose fileref basename contains the slug" do
      picked = builder_for(manifest, isolate: "b")
        .send(:isolate_members, members)
      expect(picked.map { |m| m["identifier"] }).to eq(["ISO 2"])
    end

    it "raises on a slug that matches no member" do
      expect do
        builder_for(manifest, isolate: "nope").send(:isolate_members, members)
      end.to raise_error(ArgumentError, /matched no member/)
    end
  end

  describe "#shard_log with isolate" do
    it "reports the isolate selection and the reinflate skip" do
      log = builder_for(manifest, isolate: "b").send(:shard_log, 1, 3)
      expect(log).to include('isolate "b": staging 1, skipping reinflate')
    end
  end

  describe "#reinflate_selection" do
    let(:members) { builder.send(:collection_members) }

    def reinflate_ids(shard)
      builder_for(manifest, reinflate_shard: shard)
        .send(:reinflate_selection, members).map { |m| m["identifier"] }
    end

    it "keeps every member when no reinflate shard is given" do
      expect(builder.send(:reinflate_selection, members)).to eq(members)
    end

    it "selects the members matching index % total, in order" do
      expect(reinflate_ids([0, 2])).to eq(["ISO 1", "ISO 3"])
      expect(reinflate_ids([1, 2])).to eq(["ISO 2"])
    end

    it "partitions the members across all reinflate shards of a total" do
      picked = (0...3).flat_map do |i|
        builder_for(manifest, reinflate_shard: [i, 3])
          .send(:reinflate_selection, members)
      end
      expect(picked).to eq(members)
    end
  end

  describe "#reinflate_render_options with a reinflate shard" do
    let(:members) { builder.send(:collection_members) }

    it "restricts the rendered members to the slice's identifiers" do
      slice = builder_for(manifest, reinflate_shard: [1, 2])
        .send(:reinflate_selection, members)
      opts = builder_for(manifest, reinflate_shard: [1, 2])
        .send(:reinflate_render_options, slice)
      expect(opts[:only_members]).to eq(["ISO 2"])
    end

    it "sets no render restriction without a reinflate shard" do
      expect(builder.send(:reinflate_render_options, members))
        .not_to have_key(:only_members)
    end
  end

  describe "#with_stubbed_members" do
    # Positional stub docrefs as stored_docrefs would emit them for the
    # members of the manifest above (ISO 1, ISO 2, ISO 3).
    let(:docrefs) do
      [0, 1, 2].map do |i|
        { "fileref" => "/tmp/reinf/member_#{i}.xml",
          "identifier" => "ISO #{i + 1}" }
      end
    end

    let(:stubbed_tree) do
      builder.send(:with_stubbed_members, builder.send(:manifest),
                   docrefs, [0], "/tmp/reinf")
    end

    it "preserves the tree and swaps only member entries" do
      subs = stubbed_tree.dig("manifest", "manifest")
      expect(subs[0]["docref"].map { |d| d["fileref"] }).to eq(
        %w[/tmp/reinf/member_0.xml /tmp/reinf/member_1.xml],
      )
    end

    it "swaps a single-docref hash entry" do
      subs = stubbed_tree.dig("manifest", "manifest")
      expect(subs[1]["docref"]).to eq(
        "fileref" => "/tmp/reinf/member_2.xml", "identifier" => "ISO 3",
      )
    end

    it "absolutizes attachment filerefs" do
      subs = stubbed_tree.dig("manifest", "manifest")
      expect(subs[2]["docref"][0]["fileref"]).to end_with("/logo.svg")
    end
  end

  describe "nested manifest attachment carryover (suma#169)" do
    let(:fixture_dir) { Dir.mktmpdir }

    let(:builder) do
      described_class.new(
        collection_config_path: File.join(fixture_dir,
                                          "collection-output.yaml"),
        output_directory: File.join(fixture_dir, "_site"),
      )
    end

    # Where write_reinflate_manifest writes the reinflate manifest: the
    # directory carried filerefs must resolve from.
    let(:reinf_dir) { File.join(fixture_dir, "_site", "_staged_reinflate") }
    let(:rebuilt) do
      builder.send(:with_stubbed_members,
                   builder.send(:manifest)["manifest"], stub_docrefs, [0],
                   reinf_dir)
    end

    # As stored_docrefs would emit them for the two members, in order.
    def stub_docrefs
      [{ "fileref" => "member_0.xml", "identifier" => "uuid-p41" },
       { "fileref" => "member_1.xml", "identifier" => "uuid-p42" }]
    end

    before { write_nested_fixture(fixture_dir) }

    # The node write_reinflate_manifest grafts as the entry after the
    # part 41 stub.
    def carried_node
      rebuilt["docref"][1]
    end

    def carried_entries
      carried_node["docref"]
    end

    # A collection manifest referencing two nested part manifests, as the
    # ISO 10303 corpus emits them: part 41 declares a direct .exp and
    # .html attachment and a grouping entry referencing a shared manifest
    # that declares a further .exp attachment; part 42 declares none.
    def write_nested_fixture(dir)
      write_fixture_sources(dir)
      write_fixture_manifests(dir)
    end

    def write_fixture_sources(dir)
      FileUtils.mkdir_p([
                          File.join(dir, "documents", "p41"),
                          File.join(dir, "documents", "p42"),
                          File.join(dir, "plain_schemas", "resources", "s1"),
                          File.join(dir, "plain_schemas", "resources", "s3"),
                          File.join(dir, "schema_docs", "s1"),
                          File.join(dir, "shared"),
                        ])
      { "plain_schemas/resources/s1/s1.exp" => "(* s1 *)",
        "plain_schemas/resources/s3/s3.exp" => "(* s3 *)",
        "schema_docs/s1/doc_s1.html" => "<html/>",
        "documents/p41/document.adoc" => "== Part 41" }.each do |rel, content|
        File.write(File.join(dir, rel), content)
      end
    end

    def write_fixture_manifests(dir)
      write_part_manifests(dir)
      File.write(File.join(dir, "collection-output.yaml"),
                 YAML.dump(top_manifest))
    end

    def write_part_manifests(dir)
      File.write(File.join(dir, "shared/schemas.yml"),
                 YAML.dump("manifest" => shared_manifest))
      File.write(File.join(dir, "documents/p41/collection.yml"),
                 YAML.dump(part_manifest))
      File.write(File.join(dir, "documents/p42/collection.yml"),
                 YAML.dump("manifest" => plain_part_manifest))
    end

    def shared_manifest
      {
        "level" => "attachments", "title" => "Shared",
        "docref" => [{ "fileref" => "../plain_schemas/resources/s3/s3.exp",
                       "identifier" => "s3.exp", "attachment" => true }]
      }
    end

    def plain_part_manifest
      {
        "level" => "collection", "title" => "ISO Collection",
        "docref" => [{ "level" => "document",
                       "docref" => [{ "fileref" => "document.adoc",
                                      "identifier" => "p42" }] }]
      }
    end

    def part_manifest
      {
        "directives" => ["documents-inline"],
        "manifest" => {
          "level" => "collection", "title" => "ISO Collection",
          "docref" => [
            { "level" => "document", "title" => "Document",
              "docref" => [{ "fileref" => "document.adoc",
                             "identifier" => "p41" }] },
            { "level" => "attachments", "title" => "Attachments",
              "docref" => [
                { "fileref" => "../../plain_schemas/resources/s1/s1.exp",
                  "identifier" => "s1.exp", "attachment" => true },
                { "fileref" => "../../schema_docs/s1/doc_s1.html",
                  "identifier" => "s1.html", "attachment" => true },
                { "file" => "../../shared/schemas.yml" },
              ] },
          ]
        },
      }
    end

    def top_manifest
      {
        "directives" => ["documents-inline"],
        "bibdata" => { "title" => "Coll", "type" => "collection" },
        "manifest" => {
          "level" => "collection", "title" => "SRL", "sectionsplit" => true,
          "docref" => [
            { "identifier" => "uuid-p41", "index" => true,
              "file" => "documents/p41/collection.yml" },
            { "identifier" => "uuid-p42", "index" => true,
              "file" => "documents/p42/collection.yml" },
          ]
        },
      }
    end

    it "keeps the member stub as the entry ahead of the carried node" do
      expect(rebuilt["docref"][0])
        .to eq("fileref" => "member_0.xml", "identifier" => "uuid-p41")
    end

    it "grafts an attachments grouping node carrying the part identity" do
      expect(carried_node.slice("level", "title", "identifier"))
        .to eq("level" => "attachments", "title" => "Attachments",
               "identifier" => "uuid-p41-attachments")
    end

    it "carries the declared attachments in order, marked as attachments" do
      expect(carried_entries.map { |d| d["identifier"] })
        .to eq(%w[s1.exp s1.html s3.exp])
      expect(carried_entries).to all(include("attachment" => true))
    end

    # s3.exp comes from the shared manifest the part's grouping entry
    # references; its fileref resolves through that manifest's own
    # directory, not the part's, and it carries at the grouping entry's
    # position (last in the part's declaration order).
    it "carries attachments of manifests referenced two levels deep" do
      expect(carried_entries[2])
        .to include("fileref" => "../../plain_schemas/resources/s3/s3.exp")
    end

    it "re-expresses carried filerefs relative to the reinflate manifest" do
      expect(carried_entries.map { |d| d["fileref"] }).to eq([
                                                               "../../plain_schemas/resources/s1/s1.exp",
                                                               "../../schema_docs/s1/doc_s1.html",
                                                               "../../plain_schemas/resources/s3/s3.exp",
                                                             ])
    end

    it "resolves every carried fileref from the reinflate manifest directory" do
      carried_entries.each do |att|
        expect(File.file?(File.expand_path(att["fileref"], reinf_dir)))
          .to be(true), "#{att['fileref']} does not resolve"
      end
    end

    # The renderer truncates the leading ../ climb of an attachment
    # fileref into the output directory; the carried paths must land
    # exactly where a plain (nested-manifest-expanded) build copies them.
    it "derives the plain build's destination paths from carried filerefs" do
      dests = carried_entries
        .map { |d| d["fileref"].sub(%r{\A(\./)?(\.\./)+}, "") }
      expect(dests).to eq(["plain_schemas/resources/s1/s1.exp",
                           "schema_docs/s1/doc_s1.html",
                           "plain_schemas/resources/s3/s3.exp"])
    end

    it "carries no attachment node for a nested manifest without attachments" do
      entries = rebuilt["docref"]
      expect(entries.size).to eq(3)
      expect(entries[2])
        .to eq("fileref" => "member_1.xml", "identifier" => "uuid-p42")
    end

    it "does not carry the nested manifest's document members" do
      expect(carried_entries.map { |d| d["identifier"] })
        .not_to include("p41")
    end

    # A build invoked from the collection root passes a RELATIVE output
    # directory; the carried filerefs must still resolve (suma#169).
    def relative_output_resolves?
      reinf = File.join("_site", "_staged_reinflate")
      builder = described_class.new(
        collection_config_path: File.join(fixture_dir,
                                          "collection-output.yaml"),
        output_directory: "_site",
      )
      tree = builder.send(:with_stubbed_members,
                          builder.send(:manifest)["manifest"],
                          stub_docrefs, [0], reinf)
      fileref = tree.dig("docref", 1, "docref", 0, "fileref")
      # The render resolves the fileref from the cwd-anchored reinflate
      # directory: the same anchoring the builder computed it against.
      File.file?(File.expand_path(fileref, File.expand_path(reinf)))
    end

    it "re-expresses carried filerefs under a relative output directory" do
      expect(relative_output_resolves?).to be(true)
    end
  end

  describe "child artefact alias wiring" do
    let(:dig_path) { ["manifest", "manifest", 0, "docref", 0, "identifier"] }

    it "digs the docref identifier through the single-member manifest shape" do
      one = builder.send(:single_member_manifest,
                         "fileref" => "a.xml", "identifier" => "ISO 1")
      expect(one.dig(*dig_path)).to eq("ISO 1")
    end

    it "generates a child script that digs the same path" do
      script = builder.send(:child_script)
      expect(script)
        .to include(%(manifest.dig("manifest", "manifest", 0, "docref", 0, "identifier")))
    end

    # The child script rides to the worker in an interpolating heredoc, so
    # a stray `\A` in the source becomes `A` in the generated file: the
    # alias matcher then matches nothing and reinflate fails with "no
    # stored artefact". Pin the generated regex text, not just the source.
    it "generates a child script whose slug trim keeps its anchors" do
      script = builder.send(:child_script)
      expect(script).to include(%(.gsub(/\\A-|-\\z/, "")))
    end

    # The alias source is the collection's own bibdata keys, never a
    # produced-files delta: with concurrent workers another child's
    # render lands in the shared store mid-flight, and a delta would
    # alias other members' documents under this docref (suma#167).
    it "generates a child script that aliases from the render's bibdatas keys" do
      script = builder.send(:child_script)
      expect(script).to include("(collection.bibdatas || {}).keys")
      expect(script).not_to include("semantics_before")
    end

    # bibdatas is empty for corpus manifests (no bibdata entries), so the
    # bibdatas loop above never aliases anything: on a cold store
    # reinflate dies with "no stored artefact" (suma#181). metanorma
    # records the identifier -> docid mapping on the child's own
    # post-render manifest; the script must alias from that map too.
    it "generates a child script that aliases via the manifest identifier_aliases" do
      script = builder.send(:child_script)
      expect(script).to include("collection.manifest.identifier_aliases")
    end

    it "generates a child script whose alias loop keeps identical-slug guards" do
      script = builder.send(:child_script)
      expect(script).to include("next if src.empty? || dst.empty? || src == dst")
    end
  end

  # The warm-skip identity of one staged-store entry: the digest of the
  # rendering toolchain that produced it, banked beside the semantic XML
  # (metanorma/suma#203).
  describe Suma::StagedCollectionBuilder::StoreEntry do
    let(:stored) do
      path = File.join(dir, "doc.abc123.semantic.xml")
      File.write(path, "<semantic/>")
      path
    end
    let(:dir) { Dir.mktmpdir }

    after { FileUtils.rm_rf(dir) }

    it "reads a legacy entry as having no toolchain identity" do
      expect(described_class.toolchain_digest(stored)).to be_nil
      expect(described_class.current?(stored, "a" * 64)).to be(false)
      expect(described_class.short_digest(stored)).to eq("unknown")
    end

    it "banks the producing digest and validates entries against it" do
      described_class.bank(stored, "a" * 64)

      expect(described_class.toolchain_digest(stored)).to eq("a" * 64)
      expect(described_class.current?(stored, "a" * 64)).to be(true)
      expect(described_class.current?(stored, "b" * 64)).to be(false)
      expect(described_class.short_digest(stored)).to eq("a" * 8)
    end

    it "banks beside the entry, outside the semantic-XML glob" do
      described_class.bank(stored, "a" * 64)

      expect(Dir[File.join(dir, "*.semantic.xml")]).to eq([stored])
    end
  end

  # The durable warm-skip guarantee (metanorma/suma#203): a restored
  # store entry is trusted only when the toolchain that produced it is
  # the current one, so a store carried across a toolchain change by a
  # workflow cache re-renders instead of silently reusing stale renders
  # (TRThurman, iso-10303#858).
  describe "toolchain-validated warm-skip" do
    let(:current_digest) { Suma::Provenance.render_toolchain_digest }

    # Slugs chosen so the store filename is the identifier verbatim.
    let(:members) do
      [{ "fileref" => "a.xml", "identifier" => "ISO-1" },
       { "fileref" => "b.xml", "identifier" => "ISO-2" }]
    end
    let(:store) { Dir.mktmpdir }
    # [members left to render, the builder's provenance log for them]
    let(:unstaged_and_log) do
      with_quiet_utils_log do
        builder_with_store(store).unstaged_members(members)
      end
    end

    after { FileUtils.rm_rf(store) }

    def builder_with_store(store)
      dir = Dir.mktmpdir
      path = File.join(dir, "collection-output.yaml")
      File.write(path, "{}")
      described_class.new(collection_config_path: path,
                          output_directory: File.join(dir, "_site"),
                          store_dir: store)
    end

    # A stored semantic XML entry for +identifier+, named as the
    # metanorma ArtifactStore names them
    # (<docid-slug>.<content-hash>.semantic.xml), optionally banked with
    # a toolchain sidecar.
    def bank_entry(store, identifier, digest: nil)
      stored = File.join(store, "#{identifier}.abc123.semantic.xml")
      File.write(stored, "<semantic/>")
      described_class::StoreEntry.bank(stored, digest) if digest
      stored
    end

    def with_quiet_utils_log
      buffer = StringIO.new
      original = Suma::Utils.output
      Suma::Utils.output = buffer
      [yield, buffer.string]
    ensure
      Suma::Utils.output = original
    end

    def restored_line(identifier)
      "[staged] #{identifier}: restored from store " \
        "(toolchain #{current_digest[0, 8]})"
    end

    it "skips an entry banked under the current toolchain" do
      bank_entry(store, "ISO-1", digest: current_digest)

      expect(unstaged_and_log.first.map { |m| m["identifier"] })
        .to eq(%w[ISO-2])
      expect(unstaged_and_log.last).to include(restored_line("ISO-1"))
    end

    it "re-renders an entry banked under a different toolchain" do
      bank_entry(store, "ISO-1", digest: "0" * 64)

      expect(unstaged_and_log.first.map { |m| m["identifier"] })
        .to eq(%w[ISO-1 ISO-2])
      expect(unstaged_and_log.last).to include("[staged] ISO-1: rendering")
    end

    it "logs that a member with no entry renders" do
      expect(unstaged_and_log.first.map { |m| m["identifier"] })
        .to eq(%w[ISO-1 ISO-2])
      expect(unstaged_and_log.last).to include("[staged] ISO-1: rendering",
                                               "[staged] ISO-2: rendering")
    end

    it "re-renders a legacy entry without a banked digest" do
      stored = bank_entry(store, "ISO-1")

      expect(unstaged_and_log.first.map { |m| m["identifier"] })
        .to eq(%w[ISO-1 ISO-2])
      expect(described_class::StoreEntry.toolchain_digest(stored)).to be_nil
    end

    # The migration: banking after the re-render records the producing
    # toolchain, so the next warm-skip takes the entry (at most one extra
    # render per legacy entry, once, then the store is current).
    it "re-banks a re-rendered legacy entry with the current digest" do
      stored = bank_entry(store, "ISO-1")
      builder = builder_with_store(store)

      builder.bank_toolchains(builder.unstaged_members(members))
      expect(described_class::StoreEntry.toolchain_digest(stored)).to eq(current_digest)
    end

    it "takes a re-banked entry on the next warm-skip" do
      bank_entry(store, "ISO-1")
      builder = builder_with_store(store)
      builder.bank_toolchains(builder.unstaged_members(members))

      expect(builder.unstaged_members(members).map { |m| m["identifier"] }).to eq(%w[ISO-2])
    end
  end
end
