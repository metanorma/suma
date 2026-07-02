# frozen_string_literal: true

module Suma
  # Pure renderers for the AsciiDoc source fed to Metanorma when compiling
  # an EXPRESS schema to HTML/XML.
  #
  # Each template knows how to produce the adoc body for one compilation
  # flavour (plain HTML, or HTML with cross-reference anchors). Templates
  # have no I/O and no knowledge of the underlying ExpressSchema — they
  # only need the schema id, because the rendered adoc is consumed by
  # Liquid inside Metanorma, which fetches the schema by id from the
  # surrounding lutaml-express-index.
  #
  # Composition with the compiler lives in SchemaCompiler.
  module SchemaTemplate
    autoload :Plain, "suma/schema_template/plain"
    autoload :Document, "suma/schema_template/document"
  end
end
