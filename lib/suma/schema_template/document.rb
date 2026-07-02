# frozen_string_literal: true

module Suma
  module SchemaTemplate
    # Emits an AsciiDoc body with cross-reference anchors for every
    # schema element so other documents can deep-link into the compiled
    # HTML. Only XML is produced — the anchors only resolve against the
    # XML output, not the HTML rendering.
    class Document
      EXTENSIONS = "xml"

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

          [source%unnumbered]
          --
          {{ schema.formatted }}
          --
          {% endfor %}
          ----

        ADOC
      end

      private

      # The raw anchor block contains Liquid comments and newlines that
      # are illegal on the section header line; strip them before
      # interpolating.
      def rendered_anchors
        schema_anchors.gsub(%r{//[^\r\n]+}, "").gsub(/[\n\r]+/, "").gsub(
          /^[\n\r]/, ""
        )
      end

      def schema_anchors
        <<~HEREDOC
          // _fund_cons.liquid
          [[#{schema_id}_funds]]

          // _constants.liquid
          {% if schema.constants.size > 0 %}
          #{bookmark('constants')}
          {% for thing in schema.constants %}
          #{bookmark('{{thing.id}}')}
          {% endfor %}
          {% endif %}

          // _types.liquid
          {% if schema.types.size > 0 %}
          #{bookmark('types')}
          // _type.liquid
          {% for thing in schema.types %}
          #{bookmark('{{thing.id}}')}
          {% if thing.items.size > 0 %}
          // _type_items.liquid
          #{bookmark('{{thing.id}}.items')}
          {% for item in thing.items %}
          #{bookmark('{{thing.id}}.items.{{item.id}}')}
          {% endfor %}
          {% endif %}
          {% endfor %}
          {% endif %}

          // _entities.liquid
          {% if schema.entities.size > 0 %}
          #{bookmark('entities')}
          {% for thing in schema.entities %}
          // _entity.liquid
          #{bookmark('{{thing.id}}')}
          {% endfor %}
          {% endif %}

          // _subtype_constraints.liquid
          {% if schema.subtype_constraints.size > 0 %}
          #{bookmark('subtype_constraints')}
          // _subtype_constraint.liquid
          {% for thing in schema.subtype_constraints %}
          #{bookmark('{{thing.id}}')}
          {% endfor %}
          {% endif %}

          // _functions.liquid
          {% if schema.functions.size > 0 %}
          #{bookmark('functions')}
          // _function.liquid
          {% for thing in schema.functions %}
          #{bookmark('{{thing.id}}')}
          {% endfor %}
          {% endif %}

          // _procedures.liquid
          {% if schema.procedures.size > 0 %}
          #{bookmark('procedures')}
          // _procedure.liquid
          {% for thing in schema.procedures %}
          #{bookmark('{{thing.id}}')}
          {% endfor %}
          {% endif %}

          // _rules.liquid
          {% if schema.rules.size > 0 %}
          #{bookmark('rules')}
          // _rule.liquid
          {% for thing in schema.rules %}
          #{bookmark('{{thing.id}}')}
          {% endfor %}
          {% endif %}
        HEREDOC
      end

      def bookmark(anchor)
        mangled = anchor.gsub("}}", ' | replace: "\", "-", "-}}')
        "[[#{schema_id}.#{mangled}]]"
      end
    end
  end
end
