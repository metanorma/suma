# frozen_string_literal: true

require "suma/site_config"
require "tmpdir"
require "fileutils"

RSpec.describe Suma::SiteConfig::Config do
  let(:tmpdir) { Dir.mktmpdir("site_config_spec") }

  after do
    FileUtils.rm_rf(tmpdir)
  end

  it "round-trips a site manifest with one source file" do
    path = File.join(tmpdir, "metanorma.yml")
    File.write(path, <<~YAML)
      ---
      metanorma:
        source:
          files:
            - collection.yml
        collection:
          organization: ISO/TC 184/SC 4
          name: ISO 10303 STEP Modules and Resources Library
    YAML

    config = described_class.from_file(path)
    expect(config.metanorma.source.files).to eq(["collection.yml"])
    expect(config.metanorma.collection.organization).to eq("ISO/TC 184/SC 4")
    expect(config.metanorma.collection.name)
      .to eq("ISO 10303 STEP Modules and Resources Library")
  end

  it "defaults the files collection to empty when omitted" do
    path = File.join(tmpdir, "metanorma-minimal.yml")
    File.write(path, <<~YAML)
      ---
      metanorma:
        source: {}
    YAML

    config = described_class.from_file(path)
    expect(config.metanorma.source.files).to eq([])
  end

  describe ".from_file" do
    it "raises ENOENT when the file does not exist" do
      expect { described_class.from_file("/nonexistent/metanorma.yml") }
        .to raise_error(Errno::ENOENT)
    end
  end
end
