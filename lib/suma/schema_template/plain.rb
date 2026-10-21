# frozen_string_literal: true

module Suma
  module SchemaTemplate
    # Emits an anchored, hyperlinked AsciiDoc body for a single EXPRESS
    # schema, producing both HTML and XML outputs via Metanorma. Every
    # element cross-reference the hyperlinked source emits resolves inside
    # the rendered document through the shared anchor block.
    class Plain
      EXTENSIONS = "xml,html"
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
