# frozen_string_literal: true

require_relative "express_schema"
require_relative "schema_attachment"
require_relative "schema_document"
require_relative "schema_config"
require_relative "utils"

module Suma
  class SchemaCollection
    attr_accessor :config, :schemas, :docs, :output_path_docs, :output_path_schemas

    def initialize(config: nil, config_yaml: nil, output_path_docs: nil, output_path_schemas: nil)
      @schemas = []
      @docs = []
      @schema_name_to_docs = {}
      @output_path_docs = if output_path_docs
          Pathname.new(output_path_docs).expand_path
        else
          Pathname.new(Dir.pwd)
        end
      @output_path_schemas = if output_path_schemas
          Pathname.new(output_path_schemas).expand_path
        else
          Pathname.new(Dir.pwd)
        end

      @config = if config
          config
        elsif config_yaml
          SchemaConfig::Config.from_file(config_yaml)
        end
    end

    def doc_from_schema_name(schema_name)
      @schema_name_to_docs[schema_name]
    end

    def finalize
      @config.schemas.each do |config_schema|
        s = ExpressSchema.new(
          path: config_schema.path,
          output_path: @output_path_schemas,
        )

        klass = config_schema.schemas_only ? SchemaDocument : SchemaAttachment
        doc = klass.new(
          schema: s,
          output_path: @output_path_docs.join(s.id),
        )

        @docs << doc
        @schemas << s
        @schema_name_to_docs[s.id] = doc
      end
    end

    def compile
      finalize
      schemas.map(&:save_exp)
      docs.each(&:compile)

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
