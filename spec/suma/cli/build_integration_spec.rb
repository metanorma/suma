# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "suma/cli"
require "suma/cli/build"

# End-to-end build of the synthetic dummy collection
# (spec/fixtures/dummy_collection, suma#107): schema compilation
# (expressir), schema_docs generation, then collection rendering with
# attachments and sectionsplit, exactly as `suma build` runs in CI.
RSpec.describe Suma::Cli::Build do
  it "builds the dummy collection end to end (suma#107)" do
    with_built_dummy_collection do |workdir|
      assert_dummy_collection_outputs(workdir)
    end
  end

  def fixture_path
    File.expand_path("../../fixtures/dummy_collection", __dir__)
  end

  def with_built_dummy_collection
    Dir.mktmpdir("dummy-collection") do |tmp|
      workdir = File.join(tmp, "dummy_collection")
      FileUtils.cp_r(fixture_path, workdir)
      scrub_build_artifacts(workdir)
      Dir.chdir(workdir) do
        # start (not new.invoke): applies declared option defaults,
        # notably compile: true, exactly as the real CLI dispatch does
        described_class.start(["build", "metanorma.yml"])
      end
      yield workdir
    end
  end

  # A local manual `suma build` leaves outputs inside the fixture tree
  # (they are gitignored); scrub them so the spec always builds from
  # sources, as CI does on a fresh checkout.
  def scrub_build_artifacts(dir)
    %w[_site site schemas.yml plain_schemas schema_docs
       collection-output.yaml].each do |path|
      FileUtils.rm_rf(File.join(dir, path))
    end
    Dir.glob(File.join(dir, "**",
                       "{document.xml,document.*.xml,document.xml.html.yaml," \
                       "*.err.html,*.log.txt,*_index.html,tmp_document*}"))
      .each { |f| FileUtils.rm_rf(f) }
    Dir.glob(File.join(dir, "documents", "*", "cover.html"))
      .each { |f| FileUtils.rm_f(f) }
  end

  def assert_dummy_collection_outputs(workdir)
    aggregate_failures do
      assert_schema_outputs(workdir)
      assert_site_outputs(workdir)
    end
  end

  # schema -> document sequencing outputs
  def assert_schema_outputs(workdir)
    expect(File).to exist(File.join(workdir, "schemas.yml"))
    %w[widget_schema gadget_schema gizmo_arm gizmo_mim
       doohickey_arm doohickey_mim].each do |schema|
      expect(File)
        .to exist(File.join(workdir, "schema_docs", schema,
                            "doc_#{schema}.html"))
    end
    expect(File)
      .to exist(File.join(workdir, "plain_schemas", "gizmo", "arm.exp"))
  end

  # collection rendering outputs; under sectionsplit the split-part
  # HTMLs and the per-document *_index.html pages land at the _site
  # root, and _site/documents keeps no HTML (unsplit member outputs are
  # deleted by the sectionsplit cleanup)
  def assert_site_outputs(workdir)
    site = File.join(workdir, "_site")
    expect(File).to exist(File.join(workdir, "collection-output.yaml"))
    expect(File).to exist(File.join(site, "index.html"))
    assert_site_documents(site)
  end

  def assert_site_documents(site)
    %w[dummy100001 dummy100002 dummy100003].each do |doc|
      expect(File).to exist(File.join(site, "#{doc}_index.html"))
    end
    expect(Dir[File.join(site, "document*.html")]).not_to be_empty
    expect(File)
      .to exist(File.join(site, "schema_docs", "widget_schema",
                          "doc_widget_schema.html"))
  end
end
