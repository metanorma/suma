# frozen_string_literal: true

require "fileutils"
require "expressir"

module Suma
  class ExpressSchema
    module Type
      RESOURCE              = :resource
      APPLICATION_PROTOCOL  = :application_protocol
      MODULE_ARM            = :module_arm
      MODULE_MIM            = :module_mim
      BUSINESS_OBJECT_MODEL = :business_object_model
      CORE_MODEL            = :core_model
      STANDALONE            = :standalone

      # Classify a schema under a schema profile (default: ISO 10303).
      #
      # @param id [String, nil] schema identifier
      # @param path [String, Pathname, nil] schema file path
      # @param profile [SchemaProfile, Symbol, String, nil] schema profile
      # @return [Symbol] a Type constant value
      def self.classify(id:, path:, profile: nil)
        SchemaProfile.fetch(profile).classify(id: id, path: path)
      end
    end

    attr_accessor :path, :id, :parsed, :output_path, :is_standalone_file

    def initialize(id:, path:, output_path:, is_standalone_file: false,
                   profile: nil, cache: nil)
      @path = Pathname.new(path).expand_path
      @id = id
      @output_path = output_path
      @is_standalone_file = is_standalone_file
      @profile = profile
      @cache = cache
    end

    def type
      @type ||= classify
    end

    def parsed
      return @parsed if @parsed

      source = File.read(@path.to_s, encoding: "UTF-8")
      @parsed = @cache&.fetch_parsed(source) || parse_and_cache(source)
      Utils.log "Loaded EXPRESS schema: #{path}"
      @id = @parsed.schemas.first.id
      @parsed
    end

    def to_plain
      parsed.to_s
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

      content = with_annotations ? parsed.format(no_remarks: false) : to_plain
      File.write(filename_plain, content)
    end

    private

    def parse_and_cache(source)
      repository = Expressir::Express::Parser.from_file(@path.to_s)
      @cache&.store_parsed(source, repository)
      repository
    end

    def classify
      Type.classify(id: @id, path: @path, profile: @profile)
    end
  end
end
