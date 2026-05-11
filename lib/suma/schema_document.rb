# frozen_string_literal: true

require_relative "schema_attachment"

module Suma
  class SchemaDocument < SchemaAttachment
    def bookmark(anchor)
      a = anchor.gsub("}}", ' | replace: "\", "-"}}')
      "[[#{@id}.#{a}]]"
    end

    def schema_anchors
      <<~HEREDOC
        // _fund_cons.liquid
        [[#{@id}_funds]]

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

    def output_extensions
      "xml"
    end

    def to_adoc(path_to_schema_yaml)
      <<~HEREDOC
        = #{@schema.id}
        :lutaml-express-index: schemas; #{path_to_schema_yaml};
        :bare: true
        :mn-document-class: iso
        :mn-output-extensions: xml,html

        [lutaml_express_liquid,schemas,context]
        ----
        {% for schema in context.schemas %}

        [[#{@id}]]
        [%unnumbered,type=express]
        == #{@id} #{schema_anchors.gsub(%r{//[^\r\n]+}, '').gsub(/[\n\r]+/, '').gsub(/^[\n\r]/, '')}

        [source%unnumbered]
        --
        {{ schema.formatted }}
        --
        {% endfor %}
        ----

      HEREDOC
    end
  end
end
