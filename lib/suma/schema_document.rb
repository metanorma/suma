# frozen_string_literal: true

require_relative "schema_attachment"

module Suma
  class SchemaDocument < SchemaAttachment
    def bookmark(anchor)
      a = anchor.gsub(/\}\}/, ' | replace: "\", "-"}}')
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
      HEREDOC
    end

    #  ////
    #   TODO:
    #   % render "templates/entities", schema: schema, schema_id: schema.id, things: schema.entities, thing_prefix: root_thing_prefix, depth: 2 %
    #
    #   % render "templates/subtype_constraints", schema_id: schema.id, things: schema.subtype_constraints, thing_prefix: root_thing_prefix, depth: 2 %
    #
    #   % render "templates/functions", schema_id: schema.id, things: schema.functions, thing_prefix: root_thing_prefix, depth: 2 %
    #
    #   % render "templates/procedures", schema_id: schema.id, things: schema.procedures, thing_prefix: root_thing_prefix, depth: 2 %
    #
    #   % render "templates/rules", schema_id: schema.id, things: schema.rules, thing_prefix: root_thing_prefix, depth: 2 %
    #   ////

    def output_extensions
      "xml"
    end

    # can't use
    # :lutaml-express-index: schemas; #{path_to_schema_yaml};
    # because that kills any possibility of this file hyperlinking to other schemas
    def to_adoc(path_to_schema_yaml)
      <<~HEREDOC
        = #{@schema.id}
        :lutaml-express-index: schemas; ../../schemas-srl.yml
        :bare: true
        :mn-document-class: iso
        :mn-output-extensions: xml,html

        [lutaml,schemas,context]
        ----
        {% assign array = context.schemas | where: "id", "#{@id}" %}
        {% for schema in array %}

        [[#{@id}]]
        [%unnumbered,type=express]
        == #{@id} #{schema_anchors.gsub(%r{//[^\r\n]+}, '').gsub(/[\n\r]+/, '').gsub(/^[\n\r]/, '')}

        [source%unnumbered]
        --
        {{ schema.formatted_hyperlinked }}
        --
        {% endfor %}
        ----

      HEREDOC
    end
  end
end
