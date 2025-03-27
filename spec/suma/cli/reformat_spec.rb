# frozen_string_literal: true

require "suma/cli"
require "suma/utils"
require "suma/cli/reformat"

RSpec.describe Suma::Cli::Reformat do
  subject(:test_subject) { described_class.new }

  it "reformats EXPRESS files" do
    instance = described_class.new
    allow(instance).to receive(:run)
    instance.reformat(File.expand_path("../../fixtures", __dir__))
    expect(instance).to have_received(:run)
  end

  it "raises ENOENT error" do
    expect do
      test_subject.reformat("not-found.exp")
    end.to raise_error(Errno::ENOENT)
  end

  it "raises ArgumentError error" do
    expect do
      test_subject.reformat(File.expand_path("reformat_spec.rb", __dir__))
    end.to raise_error(ArgumentError)
  end

  it "raises ENOENT error when no files found" do
    expect do
      test_subject.reformat(File.expand_path(".", __dir__))
    end.to raise_error(Errno::ENOENT)
  end

  it "reformats EXPRESS file as changes found" do # rubocop:disable RSpec/ExampleLength
    instance = described_class.new
    allow(instance).to receive(:update_exp)
    instance.reformat(
      File.expand_path("../../fixtures/no_changes.exp", __dir__),
    )
    expect(instance).to have_received(:update_exp)
  end

  it "ignore reformatting EXPRESS file as no changes found" do # rubocop:disable RSpec/ExampleLength
    instance = described_class.new
    allow(instance).to receive(:update_exp)
    instance.reformat(
      File.expand_path("../../fixtures/changes.exp", __dir__),
    )
    expect(instance).not_to have_received(:update_exp)
  end
end
