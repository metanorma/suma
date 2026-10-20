# frozen_string_literal: true

require "digest"
require "fileutils"

module Suma
  # Content-addressed, on-disk cache of build artifacts derived from EXPRESS
  # source text.
  #
  # Two artifact kinds share one store:
  #
  # - generated `.exp` output (plain or annotated), keyed by source bytes,
  #   Expressir version, and annotation mode;
  # - parsed Expressir repositories (S6.1), keyed by source bytes, Expressir
  #   version, Suma version, and Ruby's Marshal format version.
  #
  # Those inputs fully determine the artifact, so a hit is equivalent to a
  # fresh build and the store can be shared across builds and worktrees.
  # Parsed entries are Marshal payloads: only point the cache at a directory
  # this process controls.
  class SchemaCache
    # Bump when the persisted parsed-repository contract changes.
    PARSED_FORMAT_VERSION = 1

    attr_reader :hits, :misses

    # Build the configured cache, or a null cache when caching is disabled.
    #
    # @param options [Hash] may carry :cache_dir
    # @return [SchemaCache, NullCache]
    def self.build(options = {})
      directory = options[:cache_dir] || ENV.fetch("SUMA_SCHEMA_CACHE_DIR", nil)
      return NullCache.new if directory.nil? || directory.empty?

      new(directory)
    end

    def initialize(directory)
      @directory = directory.to_s
      @hits = 0
      @misses = 0
      @counter_lock = Mutex.new
    end

    # The cached EXPRESS output for +source+, or +nil+ on a miss.
    def fetch(source, annotations:)
      path = entry_path(source, annotations: annotations)
      return unless File.exist?(path)

      File.read(path, encoding: "UTF-8")
    end

    # Cache +content+ as the output for +source+. Returns the entry path.
    def store(source, annotations:, content:)
      path = entry_path(source, annotations: annotations)
      FileUtils.mkdir_p(@directory)
      write_atomically(path, content)
      path
    end

    # The cached parsed repository for +source+, or +nil+ on a miss.
    # Hit and miss counts support the "second build parses nothing" gate.
    def fetch_parsed(source)
      path = parsed_entry_path(source)
      unless File.exist?(path)
        @counter_lock.synchronize { @misses += 1 }
        return nil
      end

      @counter_lock.synchronize { @hits += 1 }
      # Local build cache only; never point SchemaCache at an untrusted path.
      Marshal.load(File.binread(path)) # rubocop:disable Security/MarshalLoad
    end

    # Cache a parsed Expressir repository for +source+.
    def store_parsed(source, repository)
      path = parsed_entry_path(source)
      FileUtils.mkdir_p(@directory)
      write_atomically(path, Marshal.dump(repository))
      path
    end

    private

    def entry_path(source, annotations:)
      File.join(@directory, key(source, annotations: annotations))
    end

    def parsed_entry_path(source)
      File.join(@directory, parsed_key(source))
    end

    def key(source, annotations:)
      mode = annotations ? "annotated" : "plain"
      "#{Digest::SHA256.hexdigest(source)}-#{expressir_version}-#{mode}.exp"
    end

    def parsed_key(source)
      "#{Digest::SHA256.hexdigest(source)}-#{expressir_version}-" \
        "#{model_version}-#{marshal_version}.parsed"
    end

    def expressir_version
      @expressir_version ||= Expressir::VERSION
    end

    def model_version
      @model_version ||= "#{Suma::VERSION}-#{PARSED_FORMAT_VERSION}"
    end

    def marshal_version
      @marshal_version ||= "#{Marshal::MAJOR_VERSION}.#{Marshal::MINOR_VERSION}"
    end

    # Write through a sibling temp file and rename, so a concurrent reader never
    # observes a half-written entry.
    def write_atomically(path, content)
      temp = "#{path}.#{Process.pid}.tmp"
      File.binwrite(temp, content)
      File.rename(temp, path)
    ensure
      File.delete(temp) if temp && File.exist?(temp)
    end
  end
end
