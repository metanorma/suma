# frozen_string_literal: true

require "digest"
require "json"
require "fileutils"
require "pathname"

module Suma
  # Freshness decision for the rendered collection site.
  #
  # The collection render is expensive: Metanorma compiles every member
  # document. Its output is a pure function of the emitted collection manifest,
  # the source tree it references, and the rendering toolchain, so this class
  # keys those inputs, remembers the key and the produced files in the output
  # directory, and lets the processor skip the render when nothing changed.
  class SiteBuild
    STATE_FILE = ".suma-site-build.json"

    # Emitted manifests that the build itself regenerates deterministically
    # from the sources above; whether they exist yet must not change the key.
    GENERATED_FILES = %w[collection-output.yaml schemas.yml].freeze

    def initialize(root:, output_directory:, inputs: [])
      @root = File.expand_path(root)
      @output_directory = File.expand_path(output_directory)
      @extra_inputs = inputs.map { |path| File.expand_path(path) }
    end

    # @return [Array<String>] source files determining the rendered site
    def source_files
      @source_files ||= scan_sources
    end

    # The freshness key's inputs: the source scan minus the files the
    # previous build emitted into the source tree (render-extracted images
    # beside their documents). The render runs after the freshness scan
    # memoized in source_files, so those files appear mid-build; recorded
    # on the state, they stay outputs of the previous build and never
    # inputs of the next.
    def key_files
      emitted = Array(read_state&.fetch("emitted_files", nil))
      return source_files if emitted.empty?

      source_files.reject { |file| emitted.include?(relative(file)) }
    end

    # @return [String] digest of every source file and the render toolchain
    def key
      @key ||= begin
        digest = Digest::SHA256.new
        key_files.each do |file|
          digest << relative(file) << "\0"
          digest << Digest::SHA256.file(file).hexdigest << "\0"
        end
        digest << JSON.generate(Provenance.render_toolchain)
        digest.hexdigest
      end
    end

    # True when the previous render used the same inputs and every file it
    # produced is still present.
    def current?
      state = read_state
      return false unless state && state["key"] == key

      outputs = Array(state["outputs"])
      !outputs.empty? &&
        outputs.all? { |file| File.file?(File.join(@output_directory, file)) }
    end

    # Persist the key and the produced files for the next build.
    def record
      write_state("key" => key, "outputs" => output_files,
                  "emitted_files" => emitted_files)
      self
    end

    def state_path
      File.join(@output_directory, STATE_FILE)
    end

    private

    def scan_sources
      files = @extra_inputs.select { |file| File.file?(file) }
      (files + tree_files).uniq.sort
    end

    # Files present after the build that the starting scan did not see:
    # what the render wrote into the source tree.
    def emitted_files
      (scan_sources - source_files).map { |file| relative(file) }
    end

    def tree_files
      excluded = excluded_paths
      Dir.glob(File.join(@root, "**", "*")).select do |file|
        File.file?(file) &&
          excluded.none? { |path| under?(file, path) } &&
          !generated?(relative(file).tr("\\", "/"))
      end
    end

    # Files the collection render writes next to its sources. They are
    # outputs of the previous build, never inputs, so including them would
    # change the key on every run.
    def generated?(relative)
      base = File.basename(relative)
      GENERATED_FILES.include?(relative) ||
        relative.start_with?("relaton/") ||
        base.start_with?("tmp_document") ||
        base.end_with?("_index.html", ".err.html", ".log.txt") ||
        document_artifact?(relative, base)
    end

    def document_artifact?(relative, base)
      return false unless relative.start_with?("documents/")

      base == "cover.html" || base == "document.xml" ||
        (base.start_with?("document.") && base.include?(".xml"))
    end

    # Generated trees are derived from the sources above and never feed the
    # site render as inputs of their own. Bundler's install directory is a
    # dependency artifact: CI conventionally places it at vendor/bundle
    # inside the project, where it must never count as site source.
    def excluded_paths
      fixed = %w[schema_docs plain_schemas .git .bundle vendor/bundle]
        .map { |dir| File.join(@root, dir) }
      env = [ENV.fetch("SUMA_SCHEMA_CACHE_DIR", nil),
             ENV.fetch("BUNDLE_PATH", nil)]
        .compact
        .map { |dir| File.expand_path(dir, @root) }
      [@output_directory] + fixed + env
    end

    def under?(file, path)
      file == path || file.start_with?("#{path}#{File::SEPARATOR}")
    end

    def read_state
      return unless File.file?(state_path)

      JSON.parse(File.read(state_path))
    rescue JSON::ParserError
      nil
    end

    def write_state(state)
      FileUtils.mkdir_p(@output_directory)
      temp = "#{state_path}.#{Process.pid}.tmp"
      File.write(temp, "#{JSON.pretty_generate(state)}\n")
      File.rename(temp, state_path)
    ensure
      File.delete(temp) if temp && File.exist?(temp)
    end

    def output_files
      Dir.glob(File.join(@output_directory, "**", "*"))
        .select do |file|
          File.file?(file) && File.basename(file) != STATE_FILE
        end
        .map { |file| relative_to(file, @output_directory) }
        .sort
    end

    def relative(path)
      relative_to(path, @root)
    end

    def relative_to(path, base)
      Pathname.new(path).relative_path_from(Pathname.new(base)).to_s
    end
  end
end
