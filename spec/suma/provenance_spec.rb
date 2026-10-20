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

  describe "signing" do
    let(:sign_dir) { Dir.mktmpdir("suma_sign") }
    let(:sign_manifest) { File.join(sign_dir, "provenance.json") }
    let(:argv_file) { File.join(sign_dir, "argv.txt") }

    before { File.write(sign_manifest, "{}\n") }

    after { FileUtils.rm_rf(sign_dir) }

    def fake_binary(name, script)
      path = File.join(sign_dir, name)
      File.write(path, "#!/bin/sh\n#{script}\n")
      File.chmod(0o755, path)
      path
    end

    def with_path(directory)
      original = ENV.fetch("PATH", "")
      ENV["PATH"] = "#{directory}#{File::PATH_SEPARATOR}#{original}"
      yield
    ensure
      ENV["PATH"] = original
    end

    it "signs with minisign and requires a secret key" do
      fake_binary("minisign", <<~SH)
        sig=""
        prev=""
        for arg in "$@"; do
          [ "$prev" = "-x" ] && sig="$arg"
          prev="$arg"
        done
        echo signed > "$sig"
      SH
      key = File.join(sign_dir, "minisign.key")
      File.write(key, "secret")

      with_path(sign_dir) do
        expect(described_class.sign(sign_manifest, method: "minisign",
                                                   key: key))
          .to eq("#{sign_manifest}.minisig")
      end
      expect(File).to exist("#{sign_manifest}.minisig")
      expect { described_class.sign(sign_manifest, method: "minisign") }
        .to raise_error(ArgumentError, /secret key/)
    end

    it "signs with sigstore, keylessly or with a key" do
      fake_binary("cosign", <<~SH)
        bundle=""
        prev=""
        for arg in "$@"; do
          [ "$prev" = "--bundle" ] && bundle="$arg"
          prev="$arg"
        done
        printf '%s\n' "$@" > "#{argv_file}"
        echo bundle > "$bundle"
      SH

      with_path(sign_dir) do
        expect(described_class.sign(sign_manifest, method: "sigstore"))
          .to eq("#{sign_manifest}.bundle")
      end
      keyless_args = File.read(argv_file).lines.map(&:chomp)
      expect(keyless_args).to include("sign-blob", "--yes", sign_manifest)
      expect(keyless_args).not_to include("--key")

      with_path(sign_dir) do
        described_class.sign(sign_manifest, method: "sigstore",
                                            key: "signing.key")
      end
      keyed_args = File.read(argv_file).lines.map(&:chomp)
      expect(keyed_args).to include("--key", "signing.key")
    end

    it "rejects unsupported signing methods" do
      expect { described_class.sign(sign_manifest, method: "pgp") }
        .to raise_error(ArgumentError, /unsupported signing method/)
    end

    it "reports tool availability from PATH" do
      empty = File.join(sign_dir, "empty")
      FileUtils.mkdir_p(empty)
      original = ENV.fetch("PATH", "")
      begin
        ENV["PATH"] = empty
        expect(described_class.signing_available?("sigstore")).to be false
      ensure
        ENV["PATH"] = original
      end

      fake_binary("cosign", "exit 0")
      with_path(sign_dir) do
        expect(described_class.signing_available?("sigstore")).to be true
      end
      expect(described_class.signing_available?("pgp")).to be false
    end
  end
end
