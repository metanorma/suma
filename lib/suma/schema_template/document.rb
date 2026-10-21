# frozen_string_literal: true

module Suma
  module SchemaTemplate
    # Emits an AsciiDoc body with cross-reference anchors for every
    # schema element so other documents can deep-link into the compiled
    # output. Only XML is produced — the anchors only resolve against the
    # XML output, not the HTML rendering.
    class Document
      EXTENSIONS = "xml"
      include Anchors

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

          [[#{schema_id}]]
          [%unnumbered,type=express]
          == #{schema_id} #{rendered_anchors}

          [source%unnumbered,subs="+macros"]
          --
          {{ schema.formatted_hyperlinked_adoc }}
          --
          {% endfor %}
          ----

        ADOC
      end
    end
  end
end
