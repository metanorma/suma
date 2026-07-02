# frozen_string_literal: true

require "expressir"

module Suma
  LinkValidationResult = Struct.new(:file, :line, :link, :reason,
                                    keyword_init: true)

  class LinkValidator
    def initialize(index)
      @index = index
    end

    def validate(links_by_file)
      unresolved = []

      links_by_file.each do |file, links|
        line_index = build_link_line_index(file)
        validate_file(file, links, line_index, unresolved)
      end

      unresolved
    end

    private

    def build_link_line_index(file)
      content = File.read(file)
      index = {}
      content.lines.each_with_index do |line, idx|
        line.scan(/<<express:([^,>]+)(?:,[^>]+)?>>/).flatten.each do |link|
          index[link] ||= idx
        end
      end
      index
    end

    def validate_file(file, links, line_index, unresolved)
      links.each do |link|
        line_idx = line_index[link]
        next unless line_idx

        parts = link.split(".")

        if parts.size == 1
          validate_schema_only(parts[0], file, line_idx, link, unresolved)
        else
          validate_element(parts, file, line_idx, link, unresolved)
        end
      end
    end

    def validate_schema_only(schema_name, file, line_idx, link, unresolved)
      schema = @index.find_schema(schema_name)

      return if schema

      unresolved << LinkValidationResult.new(
        file: file,
        line: line_idx + 1,
        link: link,
        reason: "Schema '#{schema_name}' not found",
      )
    end

    def validate_element(parts, file, line_idx, link, unresolved)
      schema_name = parts[0]
      element_name = parts[1]

      schema = @index.find_schema(schema_name)

      unless schema
        unresolved << LinkValidationResult.new(
          file: file,
          line: line_idx + 1,
          link: link,
          reason: "Schema '#{schema_name}' not found",
        )
        return
      end

      element = @index.find_element(schema_name, element_name)

      unless element
        unresolved << LinkValidationResult.new(
          file: file,
          line: line_idx + 1,
          link: link,
          reason: "Element '#{element_name}' not found in schema '#{schema_name}'",
        )
        return
      end

      return unless parts.size > 2

      error = validate_deep_path(schema, element, parts[2..], file, line_idx,
                                 link)
      unresolved << error if error
    end

    def validate_deep_path(schema, element, path_parts, file, line_idx,
full_link)
      current = element
      current_path = "#{schema.id}.#{element.id}"

      path_parts.each do |part|
        case current
        when Expressir::Model::Declarations::Entity
          attribute = current.attributes&.find do |a|
            a.id.downcase == part.downcase
          end

          unless attribute
            return LinkValidationResult.new(
              file: file,
              line: line_idx + 1,
              link: full_link,
              reason: "Attribute '#{part}' not found in entity '#{current_path}'",
            )
          end

          current = attribute
          current_path += ".#{part}"

        when Expressir::Model::Declarations::Type
          underlying = current.underlying_type

          if underlying.is_a?(Expressir::Model::DataTypes::Enumeration)
            enum_value = underlying.items.find do |e|
              e.id.downcase == part.downcase
            end

            unless enum_value
              return LinkValidationResult.new(
                file: file,
                line: line_idx + 1,
                link: full_link,
                reason: "Enumeration value '#{part}' not found in type '#{current_path}'",
              )
            end

            current = enum_value
            current_path += ".#{part}"

          elsif underlying
            base_type = find_base_type(schema, underlying)

            unless base_type
              return LinkValidationResult.new(
                file: file,
                line: line_idx + 1,
                link: full_link,
                reason: "Base type not found for '#{current_path}'",
              )
            end

            current = base_type

          else
            return LinkValidationResult.new(
              file: file,
              line: line_idx + 1,
              link: full_link,
              reason: "Cannot navigate deeper from type '#{current_path}'",
            )
          end

        else
          return LinkValidationResult.new(
            file: file,
            line: line_idx + 1,
            link: full_link,
            reason: "Cannot navigate deeper from '#{current_path}'",
          )
        end
      end

      nil
    end

    def find_base_type(schema, type_ref)
      return nil if %w[INTEGER REAL STRING BOOLEAN NUMBER BINARY
                       LOGICAL].include?(type_ref.to_s.upcase)

      if type_ref.is_a?(String)
        find_schema_element(schema, type_ref)
      elsif type_ref.is_a?(Expressir::Model::ModelElement)
        type_ref
      end
    end

    def find_schema_element(schema, element_name)
      [
        schema.entities,
        schema.types,
        schema.constants,
        schema.functions,
        schema.rules,
        schema.procedures,
        schema.subtype_constraints,
      ].each do |collection|
        element = collection&.find do |e|
          e.id.downcase == element_name.downcase
        end
        return element if element
      end

      nil
    end
  end
end
