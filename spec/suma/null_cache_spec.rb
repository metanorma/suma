# frozen_string_literal: true

require "suma"

RSpec.describe Suma::NullCache do
  it "always misses and stores nothing" do
    cache = described_class.new
    cache.store("SRC", annotations: false, content: "PLAIN")

    expect(cache.fetch("SRC", annotations: false)).to be_nil
  end
end
