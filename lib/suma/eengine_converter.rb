# frozen_string_literal: true

require "expressir/commands/changes_import_eengine"

module Suma
  # Converts eengine comparison XML to Expressir::Changes::SchemaChange.
  #
  # Pure converter: takes XML content as a string (no I/O). The caller
  # is responsible for reading the file. This keeps the object cheap
  # to construct and easy to test in isolation — no fixture file
  # required just to instantiate.
  class EengineConverter
    def initialize(schema_name, xml_content)
      @schema_name = schema_name
      @xml_content = xml_content
    end

    # Convert the eengine XML to a ChangeSchema.
    #
    # @param version [String] Version number for this change version
    # @param existing_change_schema [Expressir::Changes::SchemaChange, nil]
    #   Existing schema to append to, or nil to create new
    # @return [Expressir::Changes::SchemaChange] The updated change schema
    def convert(version:, existing_change_schema: nil)
      Expressir::Commands::ChangesImportEengine.from_xml(
        @xml_content,
        @schema_name,
        version,
        existing_schema: existing_change_schema,
      )
    end
  end
end
