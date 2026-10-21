# frozen_string_literal: true

module Suma
  module SchemaTemplate
    # The Liquid anchor block shared by the schema document templates: one
    # [[id]] for every element an Expressir cross-reference may target, so
    # every xref the hyperlinked formatter emits resolves in the rendered
    # document. Expressir links schema-qualified element ids
    # (`schema.entity`) but bare `entity.attribute` pairs, hence the two
    # bookmark forms.
    module Anchors
      # Xref targets are always qualified by the schema's *declared* id, so
      # anchors are too — independent of the manifest key's casing.
      SCHEMA_REF = "{{ schema.id }}"

      # The raw anchor block contains Liquid comments and newlines that are
      # illegal on the section header line; strip them before interpolating.
      def rendered_anchors
        anchor_block
          .gsub(%r{//[^\r\n]+}, "")
          .gsub(/[\n\r]+/, "")
          .gsub(/^[\n\r]/, "")
      end

      private

      def anchor_block
        <<~HEREDOC
          // _fund_cons.liquid
          [[#{schema_id}_funds]]

          #{constants_and_types_anchors}

          #{entity_anchors}

          #{declaration_anchors}
        HEREDOC
      end

      def constants_and_types_anchors
        <<~HEREDOC
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
        HEREDOC
      end

      def entity_anchors
        <<~HEREDOC
          // _entities.liquid
          {% if schema.entities.size > 0 %}
          #{bookmark('entities')}
          // _entity.liquid
          {% for thing in schema.entities %}
          #{bookmark('{{thing.id}}')}
          {% for attr in thing.attributes %}
          #{bookmark_local('{{thing.id}}.{{attr.id}}')}
          {% endfor %}
          {% endfor %}
          {% endif %}
        HEREDOC
      end

      def declaration_anchors
        <<~HEREDOC
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
          #{callable_anchors}
          {% endfor %}
          {% endif %}

          // _procedures.liquid
          {% if schema.procedures.size > 0 %}
          #{bookmark('procedures')}
          // _procedure.liquid
          {% for thing in schema.procedures %}
          #{callable_anchors}
          {% endfor %}
          {% endif %}

          // _rules.liquid
          {% if schema.rules.size > 0 %}
          #{bookmark('rules')}
          // _rule.liquid
          {% for thing in schema.rules %}
          #{bookmark('{{thing.id}}')}
          {% for var in thing.variables %}
          #{bookmark_local('{{thing.id}}.{{var.id}}')}
          {% endfor %}
          {% endfor %}
          {% endif %}
        HEREDOC
      end

      # Functions and procedures carry parameters and local variables, and
      # Expressir links references to them as bare `owner.name` pairs.
      def callable_anchors
        <<~HEREDOC
          #{bookmark('{{thing.id}}')}
          {% for param in thing.parameters %}
          #{bookmark_local('{{thing.id}}.{{param.id}}')}
          {% endfor %}
          {% for var in thing.variables %}
          #{bookmark_local('{{thing.id}}.{{var.id}}')}
          {% endfor %}
        HEREDOC
      end

      def bookmark(anchor)
        "[[#{mangled(SCHEMA_REF)}.#{mangled(anchor)}]]"
      end

      def bookmark_local(anchor)
        "[[#{mangled(anchor)}]]"
      end

      def mangled(anchor)
        anchor.gsub("}}", ' | replace: "\", "-", "-}}')
      end
    end
  end
end
