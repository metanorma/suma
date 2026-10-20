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
    SIGNING_METHODS = %w[minisign sigstore].freeze

    # Sign a provenance manifest with an external tool.
    #
    # Optional by design: callers invoke this only when signing is requested.
    # minisign uses a secret key (`key:`), sigstore/cosign signs with a key or
    # keylessly when no key is given (ambient OIDC, e.g. GitHub Actions).
    #
    # @param path [String] provenance manifest
    # @param method [String] minisign or sigstore
    # @param key [String, nil] secret key path (minisign requires it)
    # @return [String] signature artifact path
    def self.sign(path, method:, key: nil)
      case method.to_s
      when "minisign"
        signature = "#{path}.minisig"
        sign_with("minisign", minisign_argv(path, key))
        signature
      when "sigstore"
        signature = "#{path}.bundle"
        sign_with("cosign", cosign_argv(path, key))
        signature
      else
        raise ArgumentError, "unsupported signing method: #{method}"
      end
    end

    # @return [Boolean] whether the signing tool is on PATH
    def self.signing_available?(method)
      case method.to_s
      when "minisign" then executable?("minisign")
      when "sigstore" then executable?("cosign")
      else false
      end
    end

    def self.minisign_argv(path, key)
      raise ArgumentError, "minisign signing requires a secret key" unless key

      ["minisign", "-S", "-W", "-s", key, "-m", path,
       "-x", "#{path}.minisig"]
    end

    def self.cosign_argv(path, key)
      argv = ["cosign", "sign-blob", "--yes",
              "--bundle", "#{path}.bundle"]
      argv += ["--key", key] if key
      argv << path
    end

    def self.sign_with(binary, argv)
      unless executable?(binary)
        raise Error, "#{binary} is not available on PATH"
      end
      return if system(*argv)

      raise Error, "#{binary} signing failed: #{argv.join(' ')}"
    end

    def self.executable?(binary)
      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |directory|
        File.executable?(File.join(directory, binary))
      end
    end

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

    private_class_method :optional_versions, :minisign_argv, :cosign_argv,
                         :sign_with, :executable?
  end
end
