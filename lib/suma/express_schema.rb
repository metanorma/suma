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
      "#{header_from_source}#{parsed.format(
        no_remarks: true, keep_untagged_remarks: true,
      )}"
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

    # expressir drops the pre-SCHEMA header comment at parse time
    # (lutaml/expressir#696); the plain face keeps it verbatim from the
    # source. The scan skips comment bodies, so a "SCHEMA" line inside a
    # header comment (ap243_open_jt mim's draft notes) is not mistaken
    # for the statement; a file with no SCHEMA statement (express-g
    # diagram stubs) is all commentary and is kept whole.
    PRE_SCHEMA_TOKEN = /
      \(\*.*?\*\)          # block comment (EXPRESS comments do not nest)
      | --[^\n]*           # line comment
      | ^[ \t]*SCHEMA\b    # the statement keyword
    /mx

    def header_from_source
      source = File.read(@path.to_s, encoding: "UTF-8")
      pos = 0
      while (match = PRE_SCHEMA_TOKEN.match(source, pos))
        return source[0, match.begin(0)] if schema_keyword?(match.to_s)

        pos = match.end(0)
      end
      source
    end

    def schema_keyword?(token)
      token.lstrip.upcase.start_with?("SCHEMA")
    end

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
