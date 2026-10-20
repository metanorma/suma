# frozen_string_literal: true

require "expressir"

module Suma
  class SchemaCollection
    attr_accessor :config, :schemas, :docs, :output_path_docs,
                  :output_path_schemas, :manifest
    attr_reader :cache

    def initialize(config: nil, config_yaml: nil, output_path_docs: nil, # rubocop:disable Metrics/ParameterLists
                   output_path_schemas: nil, manifest: nil,
                   options: { annotations: true })
      @schemas = {}
      @docs = {}
      @schema_name_to_docs = {}
      @output_path_docs = Pathname.new(output_path_docs || Dir.pwd).expand_path
      @output_path_schemas = Pathname.new(
        output_path_schemas || Dir.pwd,
      ).expand_path
      @config = config
      @config ||= config_yaml && Expressir::SchemaManifest.from_file(config_yaml)
      @manifest = manifest
      @options = options
      @cache = SchemaCache.build(@options)
    end

    def doc_from_schema_name(schema_name)
      @schema_name_to_docs[schema_name]
    end

    def finalize
      process_schemas(@config.schemas, SchemaTemplate::Plain)

      schemas_only_entries = ManifestTraverser.new(@manifest).find_schemas_only
      schemas_only_entries.each do |entry|
        next unless entry.schema_config

        process_schemas(entry.schema_config.schemas, SchemaTemplate::Document)
      end
    end

    def compile
      finalize
      targets = rebuild_targets

      exporter = SchemaExporter.new(
        schemas: targets ? schemas_for(targets) : schemas.values,
        output_path: @output_path_schemas,
        options: @options,
      )
      exporter.export

      docs_for(targets).each_value(&:compile)
      persist_build_state
    end

    # Schema ids an incremental build must re-render: changed schemas plus
    # their transitive dependents. Returns nil when a full build is required
    # (incremental disabled, outputs missing, or no prior state).
    #
    # Requires {#finalize} to have populated the collection.
    #
    # @return [Array<String>, nil]
    def rebuild_targets
      return nil unless @options[:incremental]
      return nil unless outputs_present?

      plan.rebuild
    end

    private

    def plan
      @plan ||= BuildPlan.new(
        entries: @config.schemas,
        graph: CorpusGraph.new(schemas.values.map(&:parsed)),
        previous_state: BuildPlan.read_state(state_file),
      )
    end

    def state_file
      @options[:state_file] ||
        File.join(@output_path_schemas, ".suma-build-state.json")
    end

    def outputs_present?
      File.directory?(@output_path_docs) &&
        File.directory?(@output_path_schemas)
    end

    def persist_build_state
      return unless @options[:incremental]

      BuildPlan.write_state(state_file, plan.current_state)
    end

    def schemas_for(targets)
      wanted = targets.map(&:downcase)
      schemas.values.select { |schema| wanted.include?(schema.id.downcase) }
    end

    def docs_for(targets)
      return docs unless targets

      wanted = targets.map(&:downcase)
      docs.select { |id, _compiler| wanted.include?(id.downcase) }
    end

    def process_schemas(schemas, template_class)
      schemas.each { |s| process_schema(s, template_class) }
    end

    def process_schema(config_schema, template_class)
      category = SchemaCategory.for_schema(
        id: config_schema.id, path: config_schema.path.to_s,
      )
      express = ExpressSchema.new(
        id: config_schema.id, path: config_schema.path.to_s,
        output_path: @output_path_schemas.join(category.directory).to_s,
        cache: @cache
      )

      compiler = SchemaCompiler.new(
        schema: express,
        output_path: @output_path_docs.join(express.id),
        template: template_class.new(express.id),
      )

      @docs[express.id] = compiler
      @schemas[express.id] = express
      @schema_name_to_docs[express.id] = compiler
    end
  end
end
