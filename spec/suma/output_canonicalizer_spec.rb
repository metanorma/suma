# frozen_string_literal: true

require "metanorma"
require "suma"
require "tmpdir"

RSpec.describe Suma::OutputCanonicalizer do
  subject(:canonicalizer) do
    described_class.new(output_directory: output, sources: [source])
  end

  let(:root) { Dir.mktmpdir("suma_canonicalizer") }
  let(:output) { File.join(root, "_site") }
  let(:source) { File.join(root, "collection.yml") }

  after { FileUtils.rm_rf(root) }

  before do
    FileUtils.mkdir_p(output)
    File.write(source, "manifest:\n  title: Source\n  identifier: " \
                       "aaaaaaaa-1111-4111-8111-111111111111\n")
  end

  def manifest_node(identifier, entry: [], file: nil)
    Metanorma::Collection::Config::Manifest.new(
      identifier: identifier,
      entry: entry.map do |child_id, child_file|
        manifest_node(child_id, file: child_file)
      end,
      file: file,
    )
  end

  def child(identifier, file)
    Metanorma::Collection::Config::Manifest.new(identifier: identifier,
                                                file: file)
  end

  describe "#canonicalize_manifest" do
    it "replaces generated identifiers deterministically" do
      first = manifest_node("11111111-1111-4111-8111-111111111111",
                            entry: [["22222222-2222-4222-8222-222222222222",
                                     "documents/one/collection.yml"]])
      canonicalizer.canonicalize_manifest(first)
      canonical = [first.identifier, first.entry.first.identifier]

      second = manifest_node("33333333-3333-4333-8333-333333333333",
                             entry: [["44444444-4444-4444-8444-444444444444",
                                      "documents/one/collection.yml"]])
      canonicalizer.canonicalize_manifest(second)

      expect([second.identifier, second.entry.first.identifier])
        .to eq(canonical)
      expect(canonical).to all(match(described_class::UUID_PATTERN))
    end

    it "preserves identifiers written in the sources" do
      node = manifest_node("aaaaaaaa-1111-4111-8111-111111111111")

      canonicalizer.canonicalize_manifest(node)

      expect(node.identifier)
        .to eq("aaaaaaaa-1111-4111-8111-111111111111")
    end

    it "preserves identifiers in sources carrying non-UTF-8 bytes" do
      File.binwrite(source, "id: aaaaaaaa-1111-4111-8111-111111111111\n" \
                            "note: caf\xE9\n")
      node = manifest_node("aaaaaaaa-1111-4111-8111-111111111111")

      canonicalizer.canonicalize_manifest(node)

      expect(node.identifier)
        .to eq("aaaaaaaa-1111-4111-8111-111111111111")
    end

    it "leaves non-UUID identifiers alone" do
      node = manifest_node("dummy-2026",
                           entry: [["dummy100001", "documents/one"]])
      canonicalizer.canonicalize_manifest(node)

      aggregate_failures do
        expect(node.identifier).to eq("dummy-2026")
        expect(node.entry.first.identifier).to eq("dummy100001")
      end
    end
  end

  describe "#canonicalize_documents" do
    def write_document(name, type)
      File.write(File.join(output, name), <<~XML)
        <metanorma xmlns="https://www.metanorma.org/ns/standoc" type="#{type}">
          <bibdata/>
        </metanorma>
      XML
    end

    it "replaces the random document type marker" do
      write_document("document.1.xml", "ABCDEFGH")

      canonicalizer.canonicalize_documents

      expect(File.read(File.join(output, "document.1.xml")))
        .to include('type="SUMASUMA"')
    end

    it "replaces generated UUIDs deterministically" do
      File.write(File.join(output, "collection.xml"), <<~XML)
        <collection>
          <manifest>
            <identifier>11111111-1111-4111-8111-111111111111</identifier>
          </manifest>
        </collection>
      XML
      canonicalizer.canonicalize_documents
      first = File.read(File.join(output, "collection.xml"))

      File.write(File.join(output, "collection.xml"), <<~XML)
        <collection>
          <manifest>
            <identifier>33333333-3333-4333-8333-333333333333</identifier>
          </manifest>
        </collection>
      XML
      canonicalizer.canonicalize_documents

      expect(File.read(File.join(output, "collection.xml"))).to eq(first)
    end

    it "leaves deterministic output untouched" do
      write_document("document.1.xml", "semantic")
      before = File.read(File.join(output, "document.1.xml"))

      canonicalizer.canonicalize_documents

      expect(File.read(File.join(output, "document.1.xml"))).to eq(before)
    end
  end
end
