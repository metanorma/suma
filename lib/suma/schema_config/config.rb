# frozen_string_literal: true

require "shale"
require_relative "schema"
require_relative "../utils"

module Suma
  module SchemaConfig
    class Config < Shale::Mapper
      attribute :schemas, Schema, collection: true
      attribute :path, Shale::Type::String

      def initialize(**args)
        @path = path_relative_to_absolute(path) if path
        super(**args)
      end

      def base_path
        File.dirname(@path)
      end

      yaml do
        map "schemas", using: { from: :schemas_from_yaml, to: :schemas_to_yaml }
      end

      def self.from_file(path)
        from_yaml(File.read(path)).tap do |x|
          x.set_initial_path(path)
        end
      end

      def to_file(to_path = path)
        File.open(to_path, "w") do |f|
          f.write(to_yaml)
        end
      end

      def set_initial_path(new_path)
        @path = path_relative_to_absolute(new_path)
        schemas.each do |schema|
          schema.path = path_relative_to_absolute(schema.path)
        end
      end

      def schemas_from_yaml(model, value)
        model.schemas = value.map do |k, v|
          Schema.new(id: k, path: path_relative_to_absolute(v["path"]))
        end
      end

      # TODO: I can't get the relative path working. The schemas-*.yaml file is
      # meant to contain the "path" key, which is a relative path to its
      # location, then sets the base path to each schema path, which is supposed
      # to be relative to "path" key. Somehow, the @path variable is always
      # missing in to_yaml...
      def schemas_to_yaml(model, doc)
        # puts "^"*30
        # pp self
        # pp @path
        doc["schemas"] = model.schemas.sort_by(&:id).to_h do |schema|
          [schema.id, { "path" => path_absolute_to_relative(schema.path) }]
        end
      end

      def path_relative_to_absolute(relative_path)
        eval_path = Pathname.new(relative_path)
        return relative_path if eval_path.absolute?

        # Or based on current working directory?
        return relative_path unless @path

        Pathname.new(File.dirname(@path)).join(eval_path).expand_path.to_s
      end

      def path_absolute_to_relative(absolute_path)
        # puts "path_absolute_to_relative 1 #{absolute_path}"
        # pp self
        # pp path
        # pp @hello
        return absolute_path unless @path

        relative_path = Pathname.new(absolute_path).relative_path_from(Pathname.new(@path).dirname).to_s
        # puts "path_absolute_to_relative x #{relative_path}"
        relative_path
      end

      def update_path(new_path)
        if @path.nil?
          @path = new_path
          return @path
        end

        old_base_path = File.dirname(@path)
        new_base_path = File.dirname(new_path)

        schemas.each do |schema|
          schema_path = Pathname.new(schema.path)
          next if schema_path.absolute?

          schema_path = (Pathname.new(old_base_path) + schema_path).cleanpath
          new_relative_schema_path = schema_path.relative_path_from(new_base_path)
          schema.path = new_relative_schema_path
        end

        @path = new_path
      end

      def concat(another_config)
        unless another_config.is_a?(self.class)
          raise StandardError, "Can only concatenate a non SchemaConfig::Config object."
        end

        # We need to update the relative paths when paths exist
        if path && another_config.path && path != another_config.path
          new_config = another_config.dup
          new_config.update_path(path)
        end

        schemas.concat(another_config.schemas)
      end

      def save_to_path(filename)
        new_config = dup
        new_config.path = filename
        new_config.update_base_path(File.dirname(filename))

        File.open(filename, "w") do |f|
          Utils.log "Writing #{filename}..."
          f.write(to_yaml)
          Utils.log "Done."
        end
      end
    end
  end
end
