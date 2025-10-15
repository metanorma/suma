# frozen_string_literal: true

require "expressir/commands/changes_import_eengine"

module Suma
  # Converts eengine comparison XML to Expressir::Changes::SchemaChange
  # This is a thin wrapper around Expressir's ChangesImportEengine command
  class EengineConverter
    def initialize(xml_path, schema_name)
      @xml_path = xml_path
      @schema_name = schema_name
      @xml_content = File.read(xml_path)
    end

    # Convert the eengine XML to a ChangeSchema
    #
    # @param version [String] Version number for this change edition
    # @param existing_change_schema [Expressir::Changes::SchemaChange, nil]
    #   Existing schema to append to, or nil to create new
    # @return [Expressir::Changes::SchemaChange] The updated change schema
    def convert(version:, existing_change_schema: nil)
      # Use Expressir's built-in conversion which properly handles
      # HTML elements in descriptions
      Expressir::Commands::ChangesImportEengine.from_xml(
        @xml_content,
        @schema_name,
        version,
        existing_schema: existing_change_schema,
      )
    end
  end
end
