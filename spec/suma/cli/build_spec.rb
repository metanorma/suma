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
end
