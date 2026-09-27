# frozen_string_literal: true

require "pathname"
require "expressir"

module Suma
  # Mapping validation surfaced in builds (expressir
  # TODO.suma-improvements/05): validate every module mapping.yaml —
  # its <<express:...>> links and reference paths — against the parsed
  # module corpus, and compare the drift against a committed baseline
  # so only NEW drift fails a build.
  #
  # Owns: module discovery, the shared repository parse, per-module
  # validation, and the baseline comparison. Does not own: presentation
  # and exit codes (the CLI adapter), or the validation rules
  # (Expressir::Mapping does).
  class MappingDrift
    # One drift finding; +key+ is the stable identity compared across
    # runs: "<module path>|<kind>|<detail>".
    class Entry < Lutaml::Model::Serializable
      attribute :key, :string

      key_value do
        map "key", to: :key
      end
    end

    # Serializable drift report / baseline (same wire shape).
    class Report < Lutaml::Model::Serializable
      attribute :entries, Entry, collection: true

      key_value do
        map "entries", to: :entries
      end

      def keys
        entries.map(&:key)
      end
    end

    MAPPING_GLOB = "**/mapping.yaml"
    MODULE_SCHEMAS = %w[arm.exp mim.exp].freeze
    private_constant :MAPPING_GLOB, :MODULE_SCHEMAS

    attr_reader :documents_path

    def initialize(documents_path)
      @documents_path = Pathname.new(documents_path).expand_path
    end

    # Every module mapping under documents_path that has arm/mim
    # schemas next to it.
    def discover
      Dir[documents_path.join(MAPPING_GLOB).to_s].filter_map do |mapping|
        schemas = module_schemas(File.dirname(mapping))
        { mapping: mapping, schemas: schemas } if schemas.any?
      end
    end

    # Validate every discovered module against one shared repository.
    # @return [Report]
    def scan
      modules = discover
      return Report.new(entries: []) if modules.empty?

      repository = Expressir::Express::Parser.from_files(module_closure(modules))
      Report.new(entries: modules.flat_map { |mod| drift_for(mod, repository) })
    end

    # Scan and compare against the baseline file.
    # @return [[Report, Array<String>]] the full report and the keys
    #   not present in the baseline (the NEW drift).
    def check(baseline_path)
      known = Report.from_yaml(File.read(baseline_path)).keys
      report = scan
      [report, report.keys - known]
    end

    private

    def module_schemas(dir)
      MODULE_SCHEMAS
        .map { |name| File.join(dir, name) }
        .select { |path| File.file?(path) }
    end

    def module_closure(modules)
      modules.flat_map { |mod| mod[:schemas] }.uniq
    end

    def drift_for(mod, repository)
      mapping_path = mod[:mapping]
      begin
        document = Expressir::Mapping.load_file(mapping_path)
      rescue StandardError => e
        return [Entry.new(key: entry_key(mapping_path, "load", e.message))]
      end

      unknown = Expressir::Mapping.unknown_links(document, repository)
      unknown.map do |link|
        Entry.new(key: entry_key(mapping_path, "unknown_link", link.text))
      end + refpath_issues(mapping_path, document, repository)
    end

    def refpath_issues(mapping_path, document, repository)
      Expressir::Mapping.refpaths(document).flat_map do |location, content|
        parsed = Expressir::Mapping::RefPath.parse(content)
        parse_error_entries(mapping_path, location, parsed) +
          validate_entries(mapping_path, location, parsed, repository)
      end
    end

    def parse_error_entries(mapping_path, location, parsed)
      parsed.parse_errors.map do |error|
        Entry.new(key: entry_key(mapping_path, "refpath",
                                 "#{location}: #{error}"))
      end
    end

    def validate_entries(mapping_path, location, parsed, repository)
      Expressir::Mapping::RefPath.validate(parsed, repository).map do |issue|
        detail = "#{location} [step #{issue.step}]: #{issue.message}"
        Entry.new(key: entry_key(mapping_path, "refpath", detail))
      end
    end

    def entry_key(mapping_path, kind, detail)
      "#{relative(mapping_path)}|#{kind}|#{detail}"
    end

    def relative(path)
      Pathname.new(path).expand_path.relative_path_from(documents_path).to_s
    end
  end
end
