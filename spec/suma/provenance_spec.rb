# frozen_string_literal: true

require "suma"
require "tmpdir"

RSpec.describe Suma::Provenance do
  let(:manifest) do
    File.expand_path("../fixtures/ap_publication/schemas.yaml", __dir__)
  end
  let(:exp_file) do
    File.expand_path(
      "../fixtures/ap_publication/schemas/resources/" \
      "widget_schema/widget_schema.exp",
      __dir__,
    )
  end
  let(:work_dir) { Dir.mktmpdir("suma_provenance") }
  let(:output_dir) { File.join(work_dir, "out") }
  let(:provenance_file) { File.join(work_dir, "provenance.json") }

  before do
    FileUtils.mkdir_p(output_dir)
    File.write(File.join(output_dir, "artifact.txt"), "artifact")
  end

  after { FileUtils.rm_rf(work_dir) }

  describe ".record" do
    it "digests inputs and outputs and records toolchain versions" do
      record = described_class.record(
        inputs: [manifest, exp_file], outputs: [output_dir],
      )

      expect(record["toolchain"]).to include(
        "ruby" => RUBY_VERSION,
        "expressir" => Expressir::VERSION,
        "suma" => Suma::VERSION,
      )
      expect(record["inputs"].keys).to contain_exactly(
        described_class.relative(manifest),
        described_class.relative(exp_file),
      )
      expect(record["outputs"].keys).to contain_exactly(
        described_class.relative(File.join(output_dir, "artifact.txt")),
      )
    end

    it "sorts entries for canonical output" do
      record = described_class.record(
        inputs: [manifest, exp_file], outputs: [output_dir],
      )

      expect(record["inputs"].keys).to eq(record["inputs"].keys.sort)
      expect(record["outputs"].keys).to eq(record["outputs"].keys.sort)
    end
  end

  describe ".verify" do
    it "verifies an intact manifest independently" do
      described_class.write(provenance_file, inputs: [manifest, exp_file],
                                             outputs: [output_dir])

      expect(described_class.verify(provenance_file)).to eq([])
    end

    it "reports a changed artifact" do
      described_class.write(provenance_file, inputs: [manifest],
                                             outputs: [output_dir])
      File.write(File.join(output_dir, "artifact.txt"), "tampered")

      expect(described_class.verify(provenance_file))
        .to include(a_string_matching(/\Aoutputs: changed/))
    end

    it "reports a missing input" do
      missing = File.join(work_dir, "missing.txt")
      File.write(missing, "temporary")
      described_class.write(provenance_file, inputs: [missing],
                                             outputs: [output_dir])
      FileUtils.rm_f(missing)

      expect(described_class.verify(provenance_file))
        .to include(a_string_matching(/\Ainputs: missing/))
    end
  end
end
