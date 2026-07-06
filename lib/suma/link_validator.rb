# frozen_string_literal: true

require "expressir"
require "suma/link_validation"

module Suma
  LinkValidationResult = Struct.new(:file, :line, :link, :reason,
                                    keyword_init: true)

  class LinkValidator
    autoload :Step, "suma/link_validator/step"

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
        line.scan(LinkValidation::EXPRESS_LINK_PATTERN).flatten.each do |link|
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
      context = Step::Context.new(file: file, line: line_idx, link: full_link,
                                  schema: schema, path: current_path)

      path_parts.each do |part|
        step = Step.for(current)
        return unsupported_step_failure(context) unless step

        outcome = step.new.navigate(current, part, context)
        return outcome if outcome.is_a?(LinkValidationResult)

        current = outcome
        current_path += ".#{part}"
        context.path = current_path
      end

      nil
    end

    def unsupported_step_failure(context)
      LinkValidationResult.new(
        file: context.file,
        line: context.line + 1,
        link: context.link,
        reason: "Cannot navigate deeper from '#{context.path}'",
      )
    end
  end
end
