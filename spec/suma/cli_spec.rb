# frozen_string_literal: true

require "suma/cli"
require "suma/utils"

RSpec.describe Suma do
  around(:each) do |suite|
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

  it "Build simple metanorma.yml manifest" do
    require "suma/cli/build"
    Suma::Build.start(["default_build", "metanorma.yml"])

    expect(File.exist?("schemas.yml")).to be true
    expect(File.exist?("collection-output.yaml")).to be true
  end

  it "raise ENOENT for missing manifest" do
    require "suma/cli/build"
    build = Suma::Build.new

    expect do
      build.default_build("not-found.yml")
    end.to raise_error(Errno::ENOENT)
  end

  it "non-zero exit code for missing manifest" do
    require "suma/cli/build"
    expect do
      Suma::Build.start(%w[default_build not-found.yml])
    end.to raise_error(Errno::ENOENT)
  end
end
