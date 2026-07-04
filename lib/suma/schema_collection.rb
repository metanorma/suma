# frozen_string_literal: true

require "expressir"

module Suma
  class SchemaCollection
    attr_accessor :config, :schemas, :docs, :output_path_docs,
                  :output_path_schemas, :manifest

    def initialize(config: nil, config_yaml: nil, output_path_docs: nil,
                   output_path_schemas: nil, manifest: nil)
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

      exporter = SchemaExporter.new(
        schemas: schemas.values,
        output_path: @output_path_schemas,
        options: { annotations: false },
      )
      exporter.export

      docs.each_pair do |_schema_id, compiler|
        compiler.compile
      end
    end

    private

    def process_schemas(schemas, template_class)
      schemas.each { |s| process_schema(s, template_class) }
    end

    def process_schema(config_schema, template_class)
      express = ExpressSchema.new(
        id: config_schema.id, path: config_schema.path.to_s,
        output_path: @output_path_schemas.to_s
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
