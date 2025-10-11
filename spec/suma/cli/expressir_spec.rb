# frozen_string_literal: true

require "spec_helper"
require "suma/cli"

RSpec.describe Suma::Cli::Core do
  describe "expressir subcommand" do
    it "delegates to Expressir::Cli" do
      # Verify the subcommand is registered
      expect(described_class.subcommands).to include("expressir")
      expect(described_class.subcommand_classes["expressir"]).to eq(Expressir::Cli)
    end

    it "includes expressir coverage command" do
      # Verify that expressir's coverage command is accessible
      expressir_commands = Expressir::Cli.commands
      expect(expressir_commands).to have_key("coverage")
    end

    it "includes other expressir commands" do
      # Verify that other expressir commands are accessible
      expressir_commands = Expressir::Cli.commands
      expect(expressir_commands).to have_key("format")
      expect(expressir_commands).to have_key("clean")
      expect(expressir_commands).to have_key("validate")
    end
  end
end
