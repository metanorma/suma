# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "yaml"

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

  describe "#with_stubbed_members" do
    # Positional stub docrefs as stored_docrefs would emit them for the
    # members of the manifest above (ISO 1, ISO 2, ISO 3).
    let(:docrefs) do
      [0, 1, 2].map do |i|
        { "fileref" => "/tmp/reinf/member_#{i}.xml",
          "identifier" => "ISO #{i + 1}" }
      end
    end

    it "preserves the tree and swaps only member entries" do
      builder = builder_for(manifest, coverpage: "cover.html")
      rebuilt = builder.send(:with_stubbed_members,
                             builder.send(:manifest)["manifest"], docrefs, [0])
      subs = rebuilt["manifest"]
      expect(subs[0]["title"]).to eq("Standards")
      verify_stubbed_tree(subs)
    end

    def verify_stubbed_tree(subs)
      expect(subs[0]["docref"].map { |d| d["fileref"] })
        .to eq(["/tmp/reinf/member_0.xml", "/tmp/reinf/member_1.xml"])
      expect(subs[1]["docref"]).to eq(
        { "fileref" => "/tmp/reinf/member_2.xml", "identifier" => "ISO 3" },
      )
      attach = subs[2]["docref"][0]
      expect(attach["identifier"]).to eq("logo.svg")
      expect(attach["fileref"]).to end_with("/logo.svg")
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
  end
end
