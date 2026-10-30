# frozen_string_literal: true

require "suma"

RSpec.describe Suma::Cli::Core do
  describe "build command switches" do
    it "mirrors every Cli::Build option so Core accepts them" do
      core = described_class.all_commands["build"].options.keys
      inner = Suma::Cli::Build.all_commands["build"].options.keys

      missing = inner - core
      expect(missing).to be_empty,
                         "Core is missing Cli::Build mirrors: #{missing}"
    end

    it "accepts the staged batching switches" do
      expect(described_class.all_commands["build"].options)
        .to include(:staged_workers, :staged_batch_size)
    end
  end
end
