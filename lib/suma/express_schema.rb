# frozen_string_literal: true

require_relative "utils"
require_relative "schema_cache"
require "fileutils"
require "expressir"

module Suma
  class ExpressSchema
    module Type
      RESOURCE              = :resource
      MODULE_ARM            = :module_arm
      MODULE_MIM            = :module_mim
      BUSINESS_OBJECT_MODEL = :business_object_model
      CORE_MODEL            = :core_model
      STANDALONE            = :standalone

      ID_SUFFIXES = {
        "_arm" => :MODULE_ARM,
        "_mim" => :MODULE_MIM,
        "_bom" => :BUSINESS_OBJECT_MODEL,
      }.freeze

      PATH_SEGMENTS = {
        "/resources/" => :RESOURCE,
        "/modules/" => :MODULE_ARM,
        "/core_model/" => :CORE_MODEL,
      }.freeze

      def self.classify(id:, path:)
        name = id&.downcase || ""

        ID_SUFFIXES.each do |suffix, type|
          return const_get(type) if name.end_with?(suffix)
        end

        path_str = path.to_s
        PATH_SEGMENTS.each do |segment, type|
          return const_get(type) if path_str.include?(segment)
        end

        STANDALONE
      end
    end

    attr_accessor :path, :id, :parsed, :output_path, :is_standalone_file

    def initialize(id:, path:, output_path:, is_standalone_file: false)
      @path = Pathname.new(path).expand_path
      @id = id
      @output_path = output_path
      @is_standalone_file = is_standalone_file
    end

    def type
      @type ||= classify
    end

    def parsed
      return @parsed if @parsed

      schema_content = File.read(@path.to_s)
      cache_key = Digest::SHA256.hexdigest(schema_content)
      @@cache ||= SchemaCache.new
      if (@parsed = @@cache.cache_get(cache_key))
        Utils.log "Loaded EXPRESS schema from cache"
      else
        @parsed = Expressir::Express::Parser.from_file(@path.to_s)
        Utils.log "Loaded EXPRESS schema: #{path}"
        @@cache.cache_put(cache_key, @parsed)
      end
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
        File.join(@output_path, "#{@id}.exp")
      else
        parent_dir = File.basename(File.dirname(@path))
        File.join(@output_path, parent_dir, File.basename(@path))
      end
    end

    def save_exp(with_annotations: false)
      relative_path = Pathname.new(filename_plain).relative_path_from(Dir.pwd)
      schema_type = with_annotations ? "annotated" : "plain"
      Utils.log "Save #{schema_type} schema: #{relative_path}"

      FileUtils.mkdir_p(File.dirname(filename_plain))

      content = with_annotations ? parsed.to_s(no_remarks: false) : to_plain
      File.write(filename_plain, content)
    end

    private

    def classify
      Type.classify(id: @id, path: @path)
    end
  end
end
