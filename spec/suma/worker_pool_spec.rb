# frozen_string_literal: true

require "suma"

RSpec.describe Suma::WorkerPool do
  it "maps items in input order with one worker" do
    pool = described_class.new(size: 1)
    expect(pool.map([1, 2, 3]) { |value| value * 2 }).to eq([2, 4, 6])
  end

  it "maps items in input order with several workers" do
    pool = described_class.new(size: 3)
    expect(pool.map((1..10).to_a) { |value| value * 2 })
      .to eq((1..10).map { |value| value * 2 })
  end

  it "bounds concurrency to the pool size" do
    active = 0
    peak = 0
    lock = Mutex.new
    pool = described_class.new(size: 2)

    results = pool.map((1..8).to_a) do |value|
      lock.synchronize do
        active += 1
        peak = [peak, active].max
      end
      sleep 0.02
      lock.synchronize { active -= 1 }
      value * 2
    end

    expect(results).to eq((1..8).map { |value| value * 2 })
    expect(peak).to be <= 2
    expect(peak).to be >= 2
  end

  it "propagates a worker error" do
    pool = described_class.new(size: 2)
    expect do
      pool.map([1, 2, 3]) do |value|
        raise ArgumentError, "boom" if value == 2

        value
      end
    end.to raise_error(ArgumentError, "boom")
  end

  it "rejects a non-positive size" do
    expect { described_class.new(size: 0) }
      .to raise_error(ArgumentError, /at least 1/)
  end
end
