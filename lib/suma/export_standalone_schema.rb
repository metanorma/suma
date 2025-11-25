# frozen_string_literal: true

module Suma
  # Simple schema class for standalone EXPRESS files
  # Used when exporting individual .exp files that are not part of a manifest
  class ExportStandaloneSchema
    attr_accessor :id, :path

    def initialize(id:, path:)
      @id = id
      @path = path
    end
  end
end
