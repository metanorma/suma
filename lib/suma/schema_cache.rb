# frozen_string_literal: true

require "digest"
require "fileutils"

module Suma
  # Content-addressed, on-disk cache of *generated* EXPRESS schema output --
  # the plain (annotations stripped, ISO copyright kept) or annotated `.exp`
  # text produced from a source schema.
  #
  # The cache key composes the source bytes, the Expressir version, and the
  # annotation mode. Those three fully determine the output (Expressir's
  # serialiser is deterministic), so a hit is guaranteed byte-identical to a
  # fresh generation -- and the store can be shared across builds and git
  # worktrees: identical source content hits regardless of which build wrote it.
  #
  # Supersedes the parsed-AST `Marshal` approach of metanorma/suma#35, which was
  # brittle across Ruby/Expressir versions and cached the wrong artifact (the
  # parse, not the output).
  class SchemaCache
    def initialize(directory)
      @directory = directory.to_s
    end

    # The cached output for +source+, or +nil+ on a miss.
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

    private

    def entry_path(source, annotations:)
      File.join(@directory, key(source, annotations: annotations))
    end

    def key(source, annotations:)
      mode = annotations ? "annotated" : "plain"
      "#{Digest::SHA256.hexdigest(source)}-#{expressir_version}-#{mode}.exp"
    end

    def expressir_version
      @expressir_version ||= Expressir::VERSION
    end

    # Write through a sibling temp file and rename, so a concurrent reader never
    # observes a half-written entry.
    def write_atomically(path, content)
      temp = "#{path}.#{Process.pid}.tmp"
      File.write(temp, content, encoding: "UTF-8")
      File.rename(temp, path)
    ensure
      File.delete(temp) if temp && File.exist?(temp)
    end
  end
end
