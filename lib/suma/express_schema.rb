# frozen_string_literal: true

require_relative "utils"
require "fileutils"
require "expressir"

module Suma
  class ExpressSchema
    attr_accessor :path, :id, :parsed, :output_path

    def initialize(path:, output_path:)
      @path = Pathname.new(path).expand_path
      @parsed = Expressir::Express::Parser.from_file(@path.to_s)
      Utils.log "Loaded EXPRESS schema: #{path}"

      @id = @parsed.schemas.first.id
      @output_path = output_path
    end

    def type
      case @path.to_s
      when %r{.*/resources/.*}
        "resources"
      when %r{.*/modules/.*}
        "modules"
      else
        "unknown_type"
      end
    end

    def to_plain
      @parsed.to_s(no_remarks: true)
    end

    def filename_plain
      File.join(@output_path, type, id, "#{id}.exp")
    end

    def save_exp
      relative_path = Pathname.new(filename_plain).relative_path_from(Dir.pwd)
      Utils.log "Save plain schema: #{relative_path}"

      # return if File.exist?(filename_plain)
      FileUtils.mkdir_p(File.dirname(filename_plain))

      File.open(filename_plain, "w") do |file|
        file.write(to_plain)
      end
    end
  end
end

# col = Suma::SchemaCollection.new(
#         config_yaml: 'suma-schemas.yaml',
#         output_path_docs: 'schema_docs',
#         output_path_schemas: 'plain_schemas'
#       )

# docs = col.compile

# paths = col.schemas.map do |schema|
#   {
#     plain_schema_path: schema.filename_plain,
#     schema_doc_path: col.doc_from_schema_name(schema.id).output_xml_path
#   }
# end

# Utils.log "COMPILED FILES ARE AT:"
# pp paths
