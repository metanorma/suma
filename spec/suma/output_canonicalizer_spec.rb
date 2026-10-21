# frozen_string_literal: true

require "suma"
require "tmpdir"

RSpec.describe Suma::OutputCanonicalizer do
  let(:root) { Dir.mktmpdir("suma_canonicalizer") }
  let(:output) { File.join(root, "_site") }
  let(:manifest) { File.join(root, "collection-output.yaml") }
  let(:source) { File.join(root, "collection.yml") }

  after { FileUtils.rm_rf(root) }

  before do
    FileUtils.mkdir_p(output)
    File.write(source, "manifest:\n  title: Source\n  identifier: " \
                       "aaaaaaaa-1111-4111-8111-111111111111\n")
  end

  def write_outputs(manifest_uuid, document_uuid, type)
    File.write(manifest, <<~YAML)
      ---
      manifest:
        identifier: #{manifest_uuid}
        entry:
        - identifier: #{document_uuid}
          file: documents/one/collection.yml
    YAML
    File.write(File.join(output, "collection.xml"), <<~XML)
      <collection>
        <manifest>
          <identifier>#{manifest_uuid}</identifier>
          <entry><identifier>#{document_uuid}</identifier></entry>
        </manifest>
      </collection>
    XML
    File.write(File.join(output, "document.1.xml"), <<~XML)
      <metanorma xmlns="https://www.metanorma.org/ns/standoc" type="#{type}">
        <bibdata/>
      </metanorma>
    XML
  end

  def canonicalize
    described_class.new(output_directory: output, manifest_path: manifest,
                        sources: [source]).call
  end

  def contents
    [manifest, File.join(output, "collection.xml"),
     File.join(output, "document.1.xml")].map { |file| File.read(file) }
  end

  it "canonicalizes generated UUIDs deterministically" do
    write_outputs("11111111-1111-4111-8111-111111111111",
                  "22222222-2222-4222-8222-222222222222", "ABCDEFGH")
    canonicalize
    first = contents

    write_outputs("33333333-3333-4333-8333-333333333333",
                  "44444444-4444-4444-8444-444444444444", "ZYXWVUTS")
    canonicalize

    expect(contents).to eq(first)
  end

  it "preserves UUIDs written in the sources" do
    write_outputs("aaaaaaaa-1111-4111-8111-111111111111",
                  "22222222-2222-4222-8222-222222222222", "ABCDEFGH")
    canonicalize

    expect(File.read(manifest))
      .to include("aaaaaaaa-1111-4111-8111-111111111111")
  end

  it "replaces the random document type marker" do
    write_outputs("11111111-1111-4111-8111-111111111111",
                  "22222222-2222-4222-8222-222222222222", "ABCDEFGH")
    canonicalize

    expect(File.read(File.join(output, "document.1.xml")))
      .to include('type="SUMASUMA"')
  end

  it "leaves deterministic output untouched" do
    File.write(File.join(output, "document.1.xml"),
               '<metanorma type="semantic"><bibdata/></metanorma>')
    before = File.read(File.join(output, "document.1.xml"))

    canonicalize

    expect(File.read(File.join(output, "document.1.xml"))).to eq(before)
  end
end
