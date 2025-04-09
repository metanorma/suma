# frozen_string_literal: true

require_relative "express_schema"
require_relative "schema_attachment"
require_relative "schema_document"
require_relative "schema_config"
require_relative "utils"

module Suma
  class SchemaCollection
    attr_accessor :config, :schemas, :docs, :output_path_docs, :output_path_schemas,
                  :manifest

    def initialize(config: nil, config_yaml: nil, output_path_docs: nil,
                   output_path_schemas: nil, manifest: nil)
      @schemas = {}
      @docs = {}
      @schema_name_to_docs = {}
      @output_path_docs = Pathname.new(output_path_docs || Dir.pwd).expand_path
      @output_path_schemas = Pathname.new(output_path_schemas || Dir.pwd).expand_path
      @config = config
      @config ||= config_yaml && SchemaConfig::Config.from_file(config_yaml)
      @manifest = manifest
    end

    def doc_from_schema_name(schema_name)
      @schema_name_to_docs[schema_name]
    end

    def process_schemas(schemas, klass)
      schemas.each do |config_schema|
        process_schema(config_schema, klass)
      end
    end

    def process_schema(config_schema, klass)
      s = ExpressSchema.new(
        id: config_schema.id, path: config_schema.path.to_s,
        output_path: @output_path_schemas.to_s
      )

      doc = klass.new(
        schema: s, output_path: @output_path_docs.join(s.id),
      )

      @docs[s.id] = doc
      @schemas[s.id] = s
      @schema_name_to_docs[s.id] = doc
    end

    def finalize
      # Process each schema in @config.schemas
      process_schemas(@config.schemas, SchemaAttachment)

      manifest_entry = @manifest.lookup(:schemas_only, true)

      manifest_entry.each do |entry|
        next unless entry.schema_config

        # Process each schema in entry.schema_config.schemas
        process_schemas(entry.schema_config.schemas, SchemaDocument)
      end
    end

    def compile
      finalize
      schemas.each_pair do |_schema_id, entry|
        entry.save_exp
      end

      docs.each_pair do |_schema_id, entry|
        entry.compile
      end

      # TODO: make this parallel
      # Utils.log"Starting Ractor processing"
      # pool = Ractor.new do
      #   loop do
      #     Ractor.yield(Ractor.receive)
      #   end
      # end
      # workers = (1..4).map do |i|
      #   Ractor.new(pool, name: "r#{i}") do |p|
      #     loop do
      #       input = p.take
      #       Utils.log"compiling in ractor for #{input.filename_adoc}"
      #       output_value = input.compile
      #       Ractor.yield(output_value)
      #     end
      #   end
      # end
      # docs.each do |doc|
      #   pool.send(doc)
      # end
      # results = []
      # docs.size.times do
      #   results << Ractor.select(*workers)
      # end
      # pp results
    end
  end
end
