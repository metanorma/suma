# frozen_string_literal: true

require "expressir"

module Suma
  class LinkValidator
    # Per-node-type navigation strategies for +validate_deep_path+.
    #
    # Each Step handles one EXPRESS construct (entity, type, ...) and
    # knows how to walk one path segment from it. The dispatcher in
    # LinkValidator picks the right Step by +handles?+.
    #
    # Adding a new navigable construct means adding a new Step class
    # and registering it in REGISTRY — no edits to existing Steps or
    # to validate_deep_path (open/closed principle).
    module Step
      Context = Struct.new(:file, :line, :link, :schema, :path,
                           keyword_init: true)

      # Common failure-result builder. Step subclasses call this to
      # surface an unresolved link.
      module Failure
        def failure(reason, context)
          LinkValidationResult.new(
            file: context.file,
            line: context.line + 1,
            link: context.link,
            reason: reason,
          )
        end
      end

      # Navigates one path segment from an Entity by attribute name.
      class Entity
        include Failure

        def self.handles?(node)
          node.is_a?(Expressir::Model::Declarations::Entity)
        end

        def navigate(node, part, context)
          attribute = node.attributes&.find { |a| a.id.downcase == part.downcase }
          unless attribute
            return failure("Attribute '#{part}' not found in entity '#{context.path}'",
                           context)
          end

          attribute
        end
      end

      # Navigates one path segment from a Type by either enumeration
      # value (for enum types) or by re-targeting to the underlying
      # named type (for non-enum types).
      class Type
        include Failure

        PRIMITIVE_TYPE_NAMES = %w[INTEGER REAL STRING BOOLEAN NUMBER BINARY
                                  LOGICAL].freeze

        def self.handles?(node)
          node.is_a?(Expressir::Model::Declarations::Type)
        end

        def navigate(node, part, context)
          underlying = node.underlying_type
          unless underlying
            return failure("Cannot navigate deeper from type '#{context.path}'",
                           context)
          end

          if underlying.is_a?(Expressir::Model::DataTypes::Enumeration)
            navigate_enum(underlying, part, context)
          else
            navigate_underlying(underlying, context)
          end
        end

        private

        def navigate_enum(underlying, part, context)
          enum_value = underlying.items.find { |e| e.id.downcase == part.downcase }
          unless enum_value
            return failure("Enumeration value '#{part}' not found in type '#{context.path}'",
                           context)
          end

          enum_value
        end

        def navigate_underlying(underlying, context)
          base_type = resolve_base_type(context.schema, underlying)
          unless base_type
            return failure("Base type not found for '#{context.path}'",
                           context)
          end

          base_type
        end

        def resolve_base_type(schema, type_ref)
          return nil if PRIMITIVE_TYPE_NAMES.include?(type_ref.to_s.upcase)
          return find_schema_element(schema, type_ref) if type_ref.is_a?(String)

          type_ref if type_ref.is_a?(Expressir::Model::ModelElement)
        end

        def find_schema_element(schema, name)
          SchemaElementLookup.find(schema, name)
        end
      end

      # Lookup helper shared across Step classes that need to resolve
      # a named schema element (used by Type for underlying-type
      # resolution). Lives behind its own module so Steps don't reach
      # into LinkValidator's private methods.
      module SchemaElementLookup
        def self.find(schema, name)
          collections(schema).each do |collection|
            element = collection&.find { |e| e.id.downcase == name.downcase }
            return element if element
          end
          nil
        end

        def self.collections(schema)
          [
            schema.entities,
            schema.types,
            schema.constants,
            schema.functions,
            schema.rules,
            schema.procedures,
            schema.subtype_constraints,
          ]
        end
        private_class_method :collections
      end

      REGISTRY = [Entity, Type].freeze

      # Returns the Step class that handles +node+, or +nil+ if no
      # registered Step matches.
      def self.for(node)
        REGISTRY.find { |step| step.handles?(node) }
      end
    end
  end
end
