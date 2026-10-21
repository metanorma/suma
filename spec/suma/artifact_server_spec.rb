# frozen_string_literal: true

require "suma"
require "tmpdir"

RSpec.describe Suma::ArtifactServer do
  subject(:server) { described_class.new(directory) }

  let(:directory) { Dir.mktmpdir("suma_serve") }

  before do
    urn_dir = File.join(directory, "urn", "example", "tech")
    FileUtils.mkdir_p(urn_dir)
    File.write(File.join(urn_dir, "widget.json"), '{"termid":"widget"}')
    File.write(File.join(urn_dir, "widget.html"), "<h1>widget</h1>")
    File.write(File.join(directory, "index.html"), "<ul><li>index</li></ul>")
  end

  after { FileUtils.rm_rf(directory) }

  def response(path, accept = nil)
    server.call(path, accept)
  end

  it "negotiates JSON when requested" do
    status, type, body = response("/urn/example/tech/widget",
                                  "application/json")

    expect(status).to eq("200")
    expect(type).to eq("application/json")
    expect(body).to include("widget")
  end

  it "defaults to HTML" do
    status, type, body = response("/urn/example/tech/widget", "text/html")

    expect(status).to eq("200")
    expect(type).to eq("text/html; charset=utf-8")
    expect(body).to include("<h1>widget</h1>")
  end

  it "serves explicit extensions as-is" do
    status, type, body = response("/urn/example/tech/widget.json", nil)

    expect(status).to eq("200")
    expect(type).to eq("application/json")
    expect(body).to include("widget")
  end

  it "serves the index at the root" do
    status, _type, body = response("/", nil)

    expect(status).to eq("200")
    expect(body).to include("index")
  end

  it "returns 404 for missing artifacts" do
    status, = response("/urn/example/tech/missing", nil)

    expect(status).to eq("404")
  end

  it "rejects path traversal" do
    status, = response("/urn/../../etc/passwd", nil)

    expect(status).to eq("404")
  end
end
