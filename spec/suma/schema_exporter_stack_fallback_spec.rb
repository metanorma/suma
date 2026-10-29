# frozen_string_literal: true

require "suma"
require "fileutils"
require "tmpdir"

# Real cache stand-in (no doubles): raises SystemStackError on the first
# fetch — simulating a worker thread overflowing on a pathological
# schema — then delegates to the real cache.
class SpecOverflowCache < Suma::SchemaCache
  attr_reader :fetch_count

  def initialize(*)
    super
    @fetch_count = 0
    @armed = true
  end

  def fetch(source, annotations:)
    @fetch_count += 1
    if @armed
      @armed = false
      raise SystemStackError, "simulated deep recursion"
    end
    super
  end
end

# Stack-overflow resilience of the export pool. A pathological schema
# (very deep AST) overflows the ~1 MB worker-thread stack during export;
# the pool must surface the SystemStackError instead of leaving silent
# holes, and SchemaExporter must retry the unexported schemas on the
# main thread (whose stack handled the same corpora on Ruby 3.3).
RSpec.describe Suma::SchemaExporter do
  let(:temp_dir) { Dir.mktmpdir }
  let(:output_path) { File.join(temp_dir, "out") }
  let(:cache_dir) { File.join(temp_dir, "cache") }
  let(:source_file) do
    File.join(temp_dir, "modules", "widget", "arm.exp").tap do |file|
      FileUtils.mkdir_p(File.dirname(file))
      File.write(file, "SCHEMA widget_arm; END_SCHEMA;")
    end
  end

  # Real subclass (no doubles): injects the overflow cache via the
  # build_cache seam the exporter already exposes.
  def build_exporter(cache)
    schema = Suma::ExpressSchema.new(
      id: "widget_arm", path: source_file, output_path: output_path,
      is_standalone_file: false
    )
    exporter = Class.new(described_class) do
      define_method(:build_cache) { cache }
    end
    exporter.new(
      schemas: [schema], output_path: output_path,
      options: { cache_dir: cache_dir, jobs: 2 }
    )
  end

  after { FileUtils.rm_rf(temp_dir) }

  it "re-raises a worker's SystemStackError instead of dropping it" do
    pool = Suma::WorkerPool.new(size: 2)
    items = (1..4).to_a
    expect do
      pool.map(items) { |i| raise SystemStackError, "boom" if i == 2 }
    end.to raise_error(SystemStackError)
  end

  it "completes the export on the main-thread fallback" do
    cache = SpecOverflowCache.new(cache_dir)
    expect { build_exporter(cache).export }.not_to raise_error
  end

  it "exactly one fetch happened on the worker before the fallback" do
    cache = SpecOverflowCache.new(cache_dir)
    build_exporter(cache).export
    expect(cache.fetch_count).to eq(2)
  end

  it "writes the exported schema file" do
    cache = SpecOverflowCache.new(cache_dir)
    build_exporter(cache).export
    out = File.join(output_path, "widget", "arm.exp")
    expect(File).to exist(out)
  end
end
