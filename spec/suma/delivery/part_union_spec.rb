# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

# The corpus ships the sharded site as per-part zips created with the
# workflow's exact command (zip -rqy PART.zip _site -x …), and the ship
# job overlays them before verification. The zip entries already carry
# the _site/ prefix, so the overlay has to extract into the packaging
# root — extracting into a _site directory nests everything to
# _site/_site/, which the recursive section/index globs keep counting
# while the site-root-anchored attachment counts (plain_schemas/**,
# schema_docs/) silently drop to zero: the #874 ship gate tripped on
# exactly that split. This spec pins the whole round trip — plant,
# zip, overlay, inventory — with the workflow's own commands, so any
# drift between the zip layout and the verifier's path anchoring fails
# here in seconds instead of on a 2-hour corpus run.
RSpec.describe "part-zip union round trip" do
  # Info-ZIP's command-line tool is the contract; the Windows CI image
  # does not ship it, and the corpus legs that consume this contract
  # run on ubuntu.
  before do
    skip "Info-ZIP zip/unzip are the contract and are unavailable here" \
      unless zip_available?
  end

  def zip_available?
    @zip_available ||= system("zip", "-v", out: File::NULL) &&
      system("unzip", "-v", out: File::NULL)
  end

  def schemas
    %w[alpha_schema beta_schema]
  end

  def members
    %w[1 2 3 4]
  end

  def write(path, content)
    path.dirname.mkpath
    path.write(content)
  end

  def plant_site(root, member_ids)
    root = Pathname.new(root)
    member_ids.each do |id|
      write(root / "_site" / "member_#{id}.xml.1.html",
            "<html><body>member #{id}</body></html>")
      write(root / "_site" / "ISO_#{id}_2025_index.html",
            "<html><body>index #{id}</body></html>")
    end
    schemas.each do |schema|
      write(root / "_site" / "plain_schemas" / "resources" / schema /
              "#{schema}.exp", "SCHEMA #{schema};\nEND_SCHEMA;\n")
      write(root / "_site" / "schema_docs" / schema /
              "doc_#{schema}.html",
            "<html><body>#{schema}</body></html>")
    end
    write(root / "_site" / ".metanorma-collection-cache" / "stub.yml", "x")
    write(root / "_site" / "_staged_reinflate" / "reinflate.yml", "x")
    root
  end

  def inventory(site_dir)
    Suma::Delivery::SiteVerifier.new(site_dir).verify.report["inventory"]
  end

  def zip_part(root, name)
    # The assemble job's exact command, exclusions included.
    system("zip", "-rqy", name, "_site",
           "-x", "_site/.metanorma-collection-cache/*",
           "-x", "_site/_staged_reinflate/*",
           chdir: root) or raise "zip failed"
    Pathname.new(root) / name
  end

  it "overlays the part zips into a site the verifier reads whole" do
    Dir.mktmpdir do |dir|
      dir = Pathname.new(dir)
      parts = members.each_slice(2).with_index.map do |slice, i|
        part_root = plant_site(dir / "part#{i}", slice)
        zip_part(part_root, "part#{i}.zip")
      end
      union_root = dir / "ship"
      union_root.mkpath
      # The ship job's overlay, fixed form: the entries carry the
      # _site/ prefix, so extraction targets the packaging root.
      parts.each do |zip_path|
        system("unzip", "-qo", zip_path.to_s, "-d", ".",
               chdir: union_root) or raise "unzip failed"
      end

      expected = { "sections" => members.size,
                   "index_pages" => members.size,
                   "schema_attachments" => schemas.size,
                   "schema_docs" => schemas.size }
      got = inventory(union_root / "_site")
      expect(got).to include(expected)
      expect(got["schema_attachments"]).to be > 0
      expect(got["schema_docs"]).to be > 0
    end
  end

  it "keeps the verifier's inventory identical through the shipping zip" do
    Dir.mktmpdir do |dir|
      dir = Pathname.new(dir)
      plant_site(dir / "assemble", members)
      original = inventory(dir / "assemble" / "_site")

      zip_path = zip_part(dir / "assemble", "srl.zip")
      consumer = dir / "consumer"
      consumer.mkpath
      system("unzip", "-qo", zip_path.to_s, "-d", ".",
             chdir: consumer) or raise "unzip failed"

      expect(inventory(consumer / "_site")).to eq(original)
    end
  end
end
