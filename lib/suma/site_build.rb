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
      @source_files ||= begin
        files = @extra_inputs.select { |file| File.file?(file) }
        (files + tree_files).uniq.sort
      end
    end

    # @return [String] digest of every source file and the render toolchain
    def key
      @key ||= begin
        digest = Digest::SHA256.new
        source_files.each do |file|
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
      write_state("key" => key, "outputs" => output_files)
      self
    end

    def state_path
      File.join(@output_directory, STATE_FILE)
    end

    private

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
    # site render as inputs of their own.
    def excluded_paths
      paths = [@output_directory,
               File.join(@root, "schema_docs"),
               File.join(@root, "plain_schemas"),
               File.join(@root, ".git")]
      cache = ENV.fetch("SUMA_SCHEMA_CACHE_DIR", nil)
      paths << File.expand_path(cache, @root) if cache && !cache.empty?
      paths
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
