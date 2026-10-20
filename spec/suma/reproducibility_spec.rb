# frozen_string_literal: true

require "suma"
require "tmpdir"

RSpec.describe "reproducible outputs" do
  let(:manifest) do
    File.expand_path("../fixtures/ap_publication/schemas.yaml", __dir__)
  end
  let(:urn_base) { "urn:iso:std:iso:10303:-2:ed-2:en" }

  def build(root)
    concepts = File.join(root, "concepts")
    register = File.join(root, "register")
    artifacts = File.join(root, "artifacts")
    FileUtils.mkdir_p(concepts)

    Suma::TermExtractor.new(manifest, concepts, urn: urn_base).call
    Suma::RegisterManifestGenerator.new(
      manifest, register,
      urn: "#{urn_base}:tech:*",
      id: "iso10303-2-express",
      ref: "ISO 10303-2 EXPRESS Concepts",
      year: 2026,
      edition: 3
    ).generate
    Suma::UrnResolver.new(
      manifest_file: manifest,
      urn: urn_base,
      concepts_dir: concepts,
      register_file: File.join(register, "register.yaml"),
    ).write(artifacts)
    File.write(
      File.join(root, "corpus.ttl"),
      Suma::OwlProjection.new(manifest, urn: urn_base).to_turtle,
    )
  end

  def files(root)
    Dir.glob(File.join(root, "**/*"))
      .select { |path| File.file?(path) }
      .to_h { |path| [path.delete_prefix("#{root}/"), path] }
  end

  it "rebuilds concepts, register, and URN artifacts byte-for-byte" do
    first = Dir.mktmpdir("suma_repro_a")
    second = Dir.mktmpdir("suma_repro_b")
    build(first)
    build(second)

    first_files = files(first)
    second_files = files(second)
    expect(first_files.keys).to eq(second_files.keys)
    expect(first_files.keys).not_to be_empty

    differing = first_files.keys.reject do |relative|
      File.binread(first_files[relative]) ==
        File.binread(second_files[relative])
    end
    expect(differing).to eq([])
  ensure
    FileUtils.rm_rf(first) if first
    FileUtils.rm_rf(second) if second
  end
end
