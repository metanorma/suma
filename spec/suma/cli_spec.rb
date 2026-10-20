# frozen_string_literal: true

require "tmpdir"
require "suma/cli"
require "suma/utils"

RSpec.describe Suma::Cli do
  around do |suite|
    Dir.mktmpdir do |tmpdir|
      fixtures_dir = File.expand_path("../fixtures", __dir__)
      FileUtils.cp_r(
        Dir.entries(fixtures_dir)
          .reject { |e| %w[. ..].include?(e) }
          .map { |e| File.join(fixtures_dir, e) },
        tmpdir,
      )

      Dir.chdir(tmpdir) do
        suite.run
      end
    end
  end

  describe "Build command" do
    it "builds simple metanorma.yml manifest" do
      require "suma/cli/build"
      Suma::Cli::Build.start(["build", "metanorma.yml"])

      expect(File.exist?("schemas.yml")).to be true
      expect(File.exist?("collection-output.yaml")).to be true
    end

    it "exports schemas during build successfully" do
      require "suma/cli/build"
      require "suma/schema_exporter"

      expect do
        Suma::Cli::Build.start(["build", "metanorma.yml"])
      end.not_to raise_error

      expect(File.exist?("schemas.yml")).to be true
      expect(File.exist?("collection-output.yaml")).to be true
    end

    it "raises ENOENT for missing manifest" do
      require "suma/cli/build"
      build = Suma::Cli::Build.new

      expect do
        build.build("not-found.yml")
      end.to raise_error(Errno::ENOENT)
    end

    it "returns non-zero exit code for missing manifest" do
      require "suma/cli/build"
      expect do
        Suma::Cli::Build.start(%w[build not-found.yml])
      end.to raise_error(Errno::ENOENT)
    end
  end

  describe "generate-register command" do
    it "passes edition metadata through to the register" do
      Suma::Cli::Core.start([
                              "generate-register",
                              "extract_terms/schemas-smrl-all.yml",
                              "register-out",
                              "-u", "urn:iso:std:iso:10303:-2:ed-3:en:tech:*",
                              "--id", "iso10303-2-express",
                              "--ref", "ISO 10303-2 EXPRESS Concepts",
                              "--year", "2026",
                              "--supersedes", "urn:iso:std:iso:10303:-2:ed-2",
                              "--edition", "3"
                            ])

      register = Glossarist::DatasetRegister.from_file(
        "register-out/register.yaml",
      )
      expect(register.year).to eq(2026)
      expect(register.supersedes).to eq("urn:iso:std:iso:10303:-2:ed-2")
      expect(register.tags).to include("edition:3")
    end
  end
end
