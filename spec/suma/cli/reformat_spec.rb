# frozen_string_literal: true

require "spec_helper"
require "suma/cli"
require "suma/cli/reformat"
require "suma/express_reformatter"
require "suma/utils"
require "tmpdir"
require "fileutils"

RSpec.describe Suma::Cli::Reformat do
  let(:fixtures_path) { File.expand_path("../../fixtures", __dir__) }

  describe "#reformat with a single file" do
    let(:tmpdir) { Dir.mktmpdir("suma_reformat_spec") }

    after do
      FileUtils.rm_rf(tmpdir)
    end

    it "writes the file when ExpressReformatter reports a change" do
      source = File.join(fixtures_path, "no_changes.exp")
      file = File.join(tmpdir, "schema.exp")
      FileUtils.cp(source, file)

      described_class.start(["reformat", file])

      rewritten = File.read(file)
      expect(rewritten).not_to eq(File.read(source))
    end

    it "leaves the file untouched when ExpressReformatter reports no change" do
      source = File.join(fixtures_path, "changes.exp")
      file = File.join(tmpdir, "schema.exp")
      FileUtils.cp(source, file)
      original = File.read(file)

      described_class.start(["reformat", file])

      expect(File.read(file)).to eq(original)
    end

    it "raises ArgumentError when the file is not an EXPRESS file" do
      non_exp = File.join(fixtures_path, "sample.adoc")
      expect { described_class.start(["reformat", non_exp]) }
        .to raise_error(ArgumentError, /not an EXPRESS file/)
    end

    it "raises Errno::ENOENT when the file does not exist" do
      expect { described_class.start(["reformat", "not-found.exp"]) }
        .to raise_error(Errno::ENOENT)
    end
  end

  describe "#reformat with a directory" do
    it "raises Errno::ENOENT when no EXPRESS files are found" do
      empty_dir = Dir.mktmpdir("suma_reformat_empty")
      begin
        expect { described_class.start(["reformat", empty_dir]) }
          .to raise_error(Errno::ENOENT, /No EXPRESS files found/)
      ensure
        FileUtils.rm_rf(empty_dir)
      end
    end

    it "processes every .exp file in the directory" do
      tmpdir = Dir.mktmpdir("suma_reformat_batch")
      begin
        FileUtils.cp(File.join(fixtures_path, "no_changes.exp"),
                     File.join(tmpdir, "a.exp"))
        FileUtils.cp(File.join(fixtures_path, "changes.exp"),
                     File.join(tmpdir, "b.exp"))

        expect { described_class.start(["reformat", tmpdir]) }
          .not_to raise_error

        files = Dir.glob(File.join(tmpdir, "*.exp"))
        expect(files.size).to eq(2)
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end
end
