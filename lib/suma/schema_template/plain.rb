# frozen_string_literal: true

module Suma
  module SchemaTemplate
    # Emits a plain AsciiDoc body for a single EXPRESS schema, producing
    # both HTML and XML outputs via Metanorma.
    class Plain
      EXTENSIONS = "xml,html"

      attr_reader :schema_id

      def initialize(schema_id)
        @schema_id = schema_id
      end

      def extensions
        EXTENSIONS
      end

      def render(path_to_schema_yaml)
        <<~ADOC
          = #{schema_id}
          :lutaml-express-index: schemas; #{path_to_schema_yaml};
          :bare: true
          :mn-document-class: iso
          :mn-output-extensions: #{extensions}

          [lutaml_express_liquid,schemas,context]
          ----
          {% for schema in context.schemas %}

          [%unnumbered]
          == #{schema_id}

          [source%unnumbered]
          --
          {{ schema.formatted }}
          --
          {% endfor %}
          ----

        ADOC
      end
    end
  end
end
