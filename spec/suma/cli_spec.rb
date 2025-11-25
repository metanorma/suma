# frozen_string_literal: true

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
      require "suma/export_standalone_schema"

      # This test verifies that SchemaExporter can correctly reference
      # ExportStandaloneSchema during the build process.
      expect do
        Suma::Cli::Build.start(["build", "metanorma.yml"])
      end.not_to raise_error

      # Verify that the build completed successfully
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
end
