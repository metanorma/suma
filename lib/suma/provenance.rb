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
      binary, argv, signature = signing_command(
        method: method, path: path, key: key,
      )
      sign_with(binary, argv)
      signature
    end

    # The external command and signature path for a signing method. Pure
    # apart from filesystem-free validation; exposed for cross-platform specs.
    #
    # @return [Array(String, Array<String>, String)] binary, argv, signature
    def self.signing_command(method:, path:, key: nil)
      case method.to_s
      when "minisign"
        unless key
          raise ArgumentError, "minisign signing requires a secret key"
        end

        signature = "#{path}.minisig"
        ["minisign", ["minisign", "-S", "-W", "-s", key, "-m", path,
                      "-x", signature], signature]
      when "sigstore"
        signature = "#{path}.bundle"
        argv = ["cosign", "sign-blob", "--yes",
                "--bundle", signature]
        argv += ["--key", key] if key
        argv << path
        ["cosign", argv, signature]
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

    # Gems whose versions determine rendered document bytes.
    RENDER_GEM_PREFIXES = %w[metanorma- isodoc].freeze

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

    # Toolchain identity for cached rendered documents: the provenance
    # toolchain plus every installed Metanorma/Isodoc gem, so a renderer or
    # flavor update invalidates cached renders even when source is unchanged.
    def self.render_toolchain
      @render_toolchain ||= toolchain.merge("render" => render_gems)
    end

    def self.render_gems
      gem_specs.select { |spec| render_gem?(spec.name) }
        .sort_by { |spec| [spec.name, spec.version.to_s] }
        .map { |spec| "#{spec.name}-#{spec.version}" }
    end

    def self.render_gem?(name)
      name == "metanorma" || RENDER_GEM_PREFIXES.any? do |prefix|
        name.start_with?(prefix)
      end
    end

    def self.gem_specs
      Gem::Specification.select { |spec| spec.name.match?(/\A(?:metanorma|isodoc)/) }
    end

    # @param inputs [Array<String>] files or directories
    # @param outputs [Array<String>] files or directories
    # @param exclude [Array<String>] files or directories omitted from the
    #   manifest and from the unrecorded-output check
    # @return [Hash] manifest
    def self.record(inputs:, outputs:, exclude: [])
      excluded = exclude.map { |path| File.expand_path(path) }
      {
        "toolchain" => toolchain,
        "inputs" => digests(inputs, exclude: excluded),
        "outputs" => digests(outputs, exclude: excluded),
        "output_roots" => output_roots(outputs, exclude: excluded),
        "excluded" => excluded.map { |path| relative(path) }.sort,
      }
    end

    # Write a provenance manifest as canonical JSON.
    def self.write(path, inputs:, outputs:, exclude: [])
      FileUtils.mkdir_p(File.dirname(path))
      manifest = record(inputs: inputs, outputs: outputs, exclude: exclude)
      File.write(path, "#{JSON.pretty_generate(manifest)}\n")
      path
    end

    # Independently recompute every digest in the manifest and flag files
    # that appeared under a recorded output root but are not in the manifest.
    #
    # @return [Array<String>] problems (empty = verified)
    def self.verify(path)
      manifest = JSON.parse(File.read(path))
      digest_problems(manifest) + unrecorded_outputs(manifest)
    end

    def self.digest_problems(manifest)
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

    def self.unrecorded_outputs(manifest)
      recorded = manifest.fetch("outputs", {})
      excluded = expanded(manifest["excluded"])
      Array(manifest["output_roots"]).flat_map do |root|
        output_files(root)
          .reject { |file| recorded.key?(file) || excluded?(file, excluded) }
          .map { |file| "outputs: unrecorded #{file}" }
      end.sort
    end

    def self.output_files(root)
      full_root = File.expand_path(root)
      return [] unless File.directory?(full_root)

      files([full_root]).map { |file| relative(file) }.uniq
    end

    def self.expanded(paths)
      Array(paths).map { |path| File.expand_path(path) }
    end

    def self.excluded?(relative_path, excluded)
      full = File.expand_path(relative_path)
      excluded.any? do |path|
        full == path || full.start_with?("#{path}#{File::SEPARATOR}")
      end
    end

    # @param paths [Array<String>] files or directories
    # @param exclude [Array<String>] expanded paths to skip
    # @return [Hash{String=>String}] relative path → sha256
    def self.digests(paths, exclude: [])
      files(paths)
        .reject { |file| excluded?(file, exclude) }
        .map { |file| relative(file) }
        .uniq.sort
        .to_h { |file| [file, Digest::SHA256.file(file).hexdigest] }
    end

    def self.files(paths)
      paths.flat_map do |path|
        File.directory?(path) ? Dir.glob(File.join(path, "**/*")) : [path]
      end.select { |file| File.file?(file) }
    end

    # Relative paths of the directory entries among +outputs+.
    def self.output_roots(outputs, exclude: [])
      outputs.select { |path| File.directory?(path) }
        .map { |path| relative(path) }
        .reject { |path| excluded?(path, exclude) }
        .uniq.sort
    end

    def self.relative(path)
      Pathname.new(File.expand_path(path))
        .relative_path_from(Pathname.getwd)
        .to_s
    rescue ArgumentError
      path.to_s
    end

    private_class_method :optional_versions, :sign_with, :executable?,
                         :render_gems, :render_gem?, :gem_specs,
                         :digest_problems, :unrecorded_outputs, :output_files,
                         :expanded, :excluded?, :files
  end
end
