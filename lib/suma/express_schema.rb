# frozen_string_literal: true

require_relative "utils"
require "fileutils"
require "expressir"

module Suma
  class ExpressSchema
    attr_accessor :path, :id, :parsed, :output_path, :is_standalone_file

    def initialize(id:, path:, output_path:, is_standalone_file: false)
      @path = Pathname.new(path).expand_path
      @id = id
      @output_path = output_path
      @is_standalone_file = is_standalone_file
    end

    def type
      path_str = @path.to_s
      if path_str.include?("/resources/")
        "resources"
      elsif path_str.include?("/modules/")
        "modules"
      else
        "unknown_type"
      end
    end

    def parsed
      return @parsed if @parsed

      @parsed = Expressir::Express::Parser.from_file(@path.to_s)
      Utils.log "Loaded EXPRESS schema: #{path}"
      @id = @parsed.schemas.first.id
      @parsed
    end

    def to_plain
      parsed.to_s(no_remarks: true)
    end

    def filename_plain
      ensure_id_loaded
      build_output_filename
    end

    def ensure_id_loaded
      parsed unless @id
    end

    def build_output_filename
      if @is_standalone_file
        # For standalone files, output directly to output_path
        File.join(@output_path, "#{@id}.exp")
      else
        # For manifest schemas, preserve directory structure
        # Note: @output_path already contains the category (resources/modules)
        parent_dir = File.basename(File.dirname(@path))
        File.join(@output_path, parent_dir, File.basename(@path))
      end
    end

    def save_exp(with_annotations: false)
      relative_path = Pathname.new(filename_plain).relative_path_from(Dir.pwd)
      schema_type = with_annotations ? "annotated" : "plain"
      Utils.log "Save #{schema_type} schema: #{relative_path}"

      # return if File.exist?(filename_plain)
      FileUtils.mkdir_p(File.dirname(filename_plain))

      content = with_annotations ? parsed.to_s(no_remarks: false) : to_plain
      File.write(filename_plain, content)
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
