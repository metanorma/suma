# frozen_string_literal: true

require "shale"
require_relative "schema"
require_relative "../utils"

module Suma
  module SchemaConfig
    class Config < Shale::Mapper
      attribute :schemas, Schema, collection: true
      attr_accessor :base_path, :path, :schemas_only

      def initialize(path: nil, **args)
        @path = path
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
          x.path = path
        end
      end

      def to_file(to_path = path)
        File.open(to_path, "w") do |f|
          f.write(to_yaml)
        end
      end

      def set_schemas_only
        schemas.each do |e|
          e.schemas_only = true
        end
      end

      def schemas_from_yaml(model, value)
        model.schemas = value.map do |k, v|
          Schema.new(id: k, path: v["path"], schemas_only: v["schemas-only"])
        end
      end

      def schemas_to_yaml(model, doc)
        doc["schemas"] = model.schemas.sort_by(&:id).to_h do |schema|
          [schema.id, { "path" => schema.path, "schemas-only" => schema.schemas_only }]
        end
      end

      def update_path(new_path)
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

        # We need to update the relative paths
        if path != another_config.path
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
