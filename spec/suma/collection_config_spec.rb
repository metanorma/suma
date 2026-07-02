# frozen_string_literal: true

require "suma/collection_config"
require "suma/collection_manifest"
require "tmpdir"
require "fileutils"

RSpec.describe Suma::CollectionConfig do
  let(:tmpdir) { Dir.mktmpdir("collection_config_spec") }

  let(:fixture_yml) do
    File.expand_path("../fixtures/collection.yml", __dir__)
  end

  after do
    FileUtils.rm_rf(tmpdir)
  end

  describe ".from_file" do
    it "parses the fixture collection.yml into a Config object" do
      config = described_class.from_file(fixture_yml)
      expect(config.manifest).to be_a(Suma::CollectionManifest)
      expect(config.manifest.title).to eq("ISO Collection")
      expect(config.manifest.type).to eq("collection")
    end

    it "raises ENOENT when the file does not exist" do
      expect { described_class.from_file("/nonexistent/path.yml") }
        .to raise_error(Errno::ENOENT)
    end
  end

  describe "#to_file" do
    it "round-trips the loaded fixture through YAML on disk" do
      original = described_class.from_file(fixture_yml)
      out_path = File.join(tmpdir, "round-trip.yml")
      original.to_file(out_path)

      expect(File).to exist(out_path)
      reloaded = described_class.from_file(out_path)
      expect(reloaded.manifest.title).to eq(original.manifest.title)
      expect(reloaded.manifest.type).to eq(original.manifest.type)
    end
  end
end
