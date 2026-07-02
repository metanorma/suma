# frozen_string_literal: true

require "expressir"
require "lutaml/model"

require_relative "suma/version"
require_relative "suma/processor"

module Suma
  autoload :SchemaCache, "suma/schema_cache"
  autoload :NullCache, "suma/null_cache"

  class Error < StandardError; end
  class SchemaNotFoundError < Error; end
  class CompilationError < Error; end
  class EengineNotAvailableError < Error; end
end
