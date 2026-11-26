# frozen_string_literal: true

require "suma/cli"
require "suma/cli/build"

RSpec.describe Suma::Cli::Build do
  subject(:cli) { described_class.new }

  it "raises Errno::ENOENT when the site manifest is missing" do
    expect { cli.invoke(:build, ["/nonexistent/metanorma.yml"]) }
      .to raise_error(Errno::ENOENT, /Metanorma site manifest file/)
  end

  it "declares the build command in the Thor command table" do
    expect(described_class.commands).to have_key("build")
  end

  it "accepts the --compile and --schemas-all-path options on the build command" do
    command = described_class.commands["build"]
    option_names = command.options.keys.map(&:to_s)
    expect(option_names).to include("compile")
    expect(option_names).to include("schemas_all_path")
  end

  describe "shard-exclude option" do
    it "is declared on the build command" do
      expect(described_class.commands["build"].options.keys.map(&:to_s))
        .to include("staged_shard_exclude")
    end

    it "splits comma-separated slugs" do
      expect(cli.send(:parse_excludes, " mega-104 , iso-10303-59 "))
        .to eq(["mega-104", "iso-10303-59"])
    end

    it "passes nil through when the option is absent" do
      expect(cli.send(:parse_excludes, nil)).to be_nil
    end

    it "rejects a value with no slugs" do
      expect { cli.send(:parse_excludes, " , ") }
        .to raise_error(ArgumentError, /at least one slug/)
    end
  end
end
