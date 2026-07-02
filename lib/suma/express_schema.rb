# frozen_string_literal: true

require_relative "utils"
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

    def initialize(id:, path:, output_path:, is_standalone_file: false,
                   cache: NullCache.new)
      @path = Pathname.new(path).expand_path
      @id = id
      @output_path = output_path
      @is_standalone_file = is_standalone_file
      @cache = cache
    end

    def type
      @type ||= classify
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
        File.join(@output_path, "#{@id}.exp")
      else
        parent_dir = File.basename(File.dirname(@path))
        File.join(@output_path, parent_dir, File.basename(@path))
      end
    end

    def save_exp(with_annotations: false)
      FileUtils.mkdir_p(File.dirname(filename_plain))
      File.write(filename_plain, rendered(with_annotations))
    end

    private

    # Plain/annotated output for this schema: reused from the cache when the
    # source is unchanged, otherwise generated afresh and cached. The Expressir
    # parse (the cost) happens only on a cache miss.
    def rendered(with_annotations)
      source = File.read(@path.to_s, encoding: "UTF-8")
      relative_path = Pathname.new(filename_plain).relative_path_from(Dir.pwd)
      schema_type = with_annotations ? "annotated" : "plain"

      if (cached = @cache.fetch(source, annotations: with_annotations))
        Utils.log "Save #{schema_type} schema (cached): #{relative_path}"
        return cached
      end

      Utils.log "Save #{schema_type} schema: #{relative_path}"
      generate(with_annotations).tap do |content|
        @cache.store(source, annotations: with_annotations, content: content)
      end
    end

    def generate(with_annotations)
      with_annotations ? parsed.to_s(no_remarks: false) : to_plain
    end

    def classify
      Type.classify(id: @id, path: @path)
    end
  end
end
