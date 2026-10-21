# frozen_string_literal: true

require "suma"
require "json"
require "tmpdir"

RSpec.describe Suma::SiteBuild do
  let(:root) { Dir.mktmpdir("suma_site_build") }
  let(:output) { File.join(root, "_site") }

  before do
    FileUtils.mkdir_p(output)
    FileUtils.mkdir_p(File.join(root, "documents"))
    File.write(File.join(root, "collection.yml"), "manifest: {}\n")
    File.write(File.join(root, "documents", "document.adoc"), "= Doc\n")
    File.write(File.join(output, "index.html"), "<html></html>")
  end

  after { FileUtils.rm_rf(root) }

  def site
    described_class.new(root: root, output_directory: output)
  end

  it "is stale until it records a build" do
    expect(site.current?).to be false

    site.record
    expect(site.current?).to be true
  end

  it "is stale when a source changes" do
    site.record
    File.write(File.join(root, "collection.yml"),
               "manifest: {changed: true}\n")

    expect(site.current?).to be false
  end

  it "is stale when a recorded output is missing" do
    site.record
    FileUtils.rm_f(File.join(output, "index.html"))

    expect(site.current?).to be false
  end

  it "ignores render artifacts and emitted manifests beside the sources" do
    site.record
    File.write(File.join(root, "documents", "document.xml"), "<x/>")
    File.write(File.join(root, "documents", "dummy_index.html"), "<html/>")
    File.write(File.join(root, "documents", "document.asciidoc.log.txt"),
               "log")
    File.write(File.join(root, "collection-output.yaml"), "manifest: {}\n")
    File.write(File.join(root, "schemas.yml"), "schemas: {}\n")

    expect(site.current?).to be true
  end

  it "keeps its own state out of the recorded outputs" do
    state = site.record
    entries = JSON.parse(File.read(state.state_path))["outputs"]

    expect(entries).to contain_exactly("index.html")
  end

  it "derives its key from source content" do
    key = site.key
    File.write(File.join(root, "collection.yml"),
               "manifest: {changed: true}\n")
    changed = described_class.new(root: root, output_directory: output).key

    expect(changed).not_to eq(key)
    expect(key).to match(/\A[0-9a-f]{64}\z/)
  end
end
