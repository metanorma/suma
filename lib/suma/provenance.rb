# frozen_string_literal: true

require "digest"
require "json"
require "fileutils"
require "pathname"
require "expressir"

module Suma
  # Build provenance: sha256 of every input and output artifact plus the
  # toolchain versions that produced them.
  #
  # Paths are recorded relative to the working directory so a manifest can be
  # moved with its build root. {.verify} recomputes the digests independently.
  class Provenance
    SECTIONS = %w[inputs outputs].freeze

    # @return [Hash] toolchain versions that determine output bytes
    def self.toolchain
      {
        "ruby" => RUBY_VERSION,
        "expressir" => Expressir::VERSION,
        "suma" => Suma::VERSION,
      }.merge(optional_versions)
    end

    def self.optional_versions
      versions = {}
      versions["metanorma"] = Metanorma::VERSION if defined?(Metanorma::VERSION)
      versions
    end

    # @param inputs [Array<String>] files or directories
    # @param outputs [Array<String>] files or directories
    # @return [Hash] manifest
    def self.record(inputs:, outputs:)
      {
        "toolchain" => toolchain,
        "inputs" => digests(inputs),
        "outputs" => digests(outputs),
      }
    end

    # Write a provenance manifest as canonical JSON.
    def self.write(path, inputs:, outputs:)
      FileUtils.mkdir_p(File.dirname(path))
      manifest = record(inputs: inputs, outputs: outputs)
      File.write(path, "#{JSON.pretty_generate(manifest)}\n")
      path
    end

    # Independently recompute every digest in the manifest.
    #
    # @return [Array<String>] problems (empty = verified)
    def self.verify(path)
      manifest = JSON.parse(File.read(path))
      SECTIONS.flat_map do |section|
        manifest.fetch(section, {}).filter_map do |relative, digest|
          full = File.expand_path(relative)
          if !File.exist?(full)
            "#{section}: missing #{relative}"
          elsif Digest::SHA256.file(full).hexdigest != digest
            "#{section}: changed #{relative}"
          end
        end
      end
    end

    # @param paths [Array<String>] files or directories
    # @return [Hash{String=>String}] relative path → sha256
    def self.digests(paths)
      files = paths.flat_map do |path|
        File.directory?(path) ? Dir.glob(File.join(path, "**/*")) : [path]
      end
      files.select { |file| File.file?(file) }
        .map { |file| relative(file) }
        .uniq.sort
        .to_h { |file| [file, Digest::SHA256.file(file).hexdigest] }
    end

    def self.relative(path)
      Pathname.new(File.expand_path(path))
        .relative_path_from(Pathname.getwd)
        .to_s
    rescue ArgumentError
      path.to_s
    end

    private_class_method :optional_versions
  end
end
