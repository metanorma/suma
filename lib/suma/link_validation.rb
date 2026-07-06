# frozen_string_literal: true

require "pathname"
require "expressir"

module Suma
  # Deep module behind the EXPRESS cross-reference validation pipeline.
  #
  # Interface: paths in, +Result+ out. The CLI is a thin adapter that
  # constructs this object and prints the result.
  #
  # Owns: loading the schemas manifest, discovering + reading .adoc and
  # .exp files, extracting express cross-reference links, loading parsed
  # schemas into a +SchemaIndex+, delegating to +LinkValidator+ for the
  # actual resolution, and writing the summary file.
  #
  # Does not own: presentation (use +LinkValidation.generate_summary+),
  # command-line argument parsing (the CLI adapter does that), or the
  # link-resolution rules themselves (that is +LinkValidator+'s job).
  class LinkValidation
    EXPRESS_LINK_PATTERN = /<<express:([^,>]+)(?:,[^>]+)?>>/

    attr_reader :schemas_file, :documents_path, :output_file,
                :progress, :logger

    def initialize(schemas_file:, documents_path:, output_file:,
                   progress: NullProgress.new, logger: Utils)
      @schemas_file = Pathname.new(schemas_file).expand_path
      @documents_path = Pathname.new(documents_path).expand_path
      @output_file = output_file && Pathname.new(output_file).expand_path
      @progress = progress
      @logger = logger
    end

    def call
      config = load_schemas_config
      exp_files = collect_schema_paths(config)
      adoc_files = find_adoc_files
      links_by_file = extract_links(adoc_files + exp_files)
      unresolved = validate_links(config, links_by_file)
      result = Result.new(
        adoc_count: adoc_files.size,
        exp_count: exp_files.size,
        total_links: links_by_file.values.sum(&:size),
        unresolved: unresolved,
      )
      write_summary(result) if output_file
      result
    end

    def self.generate_summary(result)
      lines = []
      lines << "Validation complete. Checked #{result.total_links} links."
      if result.success?
        lines << "✅ All links resolved successfully!"
      else
        lines << "❌ Found #{result.unresolved.size} unresolved links:"
        result.unresolved.each { |issue| lines << format_issue(issue) }
      end
      lines.join("\n")
    end

    def self.format_issue(issue)
      "#{issue.file}:#{issue.line} - " \
        "<<express:#{issue.link}>> - #{issue.reason}"
    end
    private_class_method :format_issue

    # Default no-op progress adapter. Callers that want a real progress
    # bar pass an object responding to +#start(title, total)+ and
    # +#increment+; this satisfies the same interface without forcing
    # the dependency.
    class NullProgress
      def start(_title, _total); end

      def increment; end
    end

    Result = Struct.new(
      :adoc_count,
      :exp_count,
      :total_links,
      :unresolved,
      keyword_init: true,
    ) do
      def success?
        unresolved.empty?
      end
    end

    private

    def load_schemas_config
      Expressir::SchemaManifest.from_yaml(File.read(schemas_file))
        .tap { |c| c.set_initial_path(schemas_file.to_s) }
    rescue StandardError => e
      raise Error, "Error loading schemas file: #{e.message}"
    end

    def collect_schema_paths(schemas_config)
      schemas_config.schemas.filter_map(&:path)
    end

    def find_adoc_files
      Dir.glob(documents_path.join("**", "*.adoc").to_s)
    end

    def extract_links(files)
      links_by_file = {}
      progress.start("Processing files", files.size)
      files.each do |file|
        links = extract_links_from_file(file)
        links_by_file[file] = links if links&.any?
      end
      links_by_file
    end

    def extract_links_from_file(file)
      progress.increment
      content = File.read(file)
      content.scan(EXPRESS_LINK_PATTERN).flatten.uniq
    rescue StandardError => e
      logger.log "Warning: Could not read file #{file}: #{e.message}"
      nil
    end

    def validate_links(schemas_config, links_by_file)
      paths_by_id = schemas_config.schemas.to_h { |s| [s.id, s.path] }
      progress.start("Loading schemas", paths_by_id.size)
      repo = Expressir::Express::Parser.from_files(paths_by_id.values) do |*_args|
        progress.increment
      end
      index = SchemaIndex.new(repo)
      LinkValidator.new(index).validate(links_by_file)
    end

    def write_summary(result)
      FileUtils.mkdir_p(output_file.dirname)
      File.write(output_file, self.class.generate_summary(result))
    rescue StandardError => e
      logger.log "Error writing to output file: #{e.message}"
    end
  end
end
