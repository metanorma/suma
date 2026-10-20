# frozen_string_literal: true

require "lutaml/model"
require "expressir/changes"

module Suma
  # One typed change entry: which element changed, how, and whether the
  # change is additive/compatible/breaking/editorial.
  class ChangeEntry < Lutaml::Model::Serializable
    attribute :element, :string
    attribute :element_type, :string
    attribute :action, :string
    attribute :classification, :string
    attribute :description, :string, collection: true

    yaml do
      map "element", to: :element
      map "element_type", to: :element_type
      map "action", to: :action
      map "classification", to: :classification
      map "description", to: :description
    end
  end

  # The typed change manifest for one schema edition pair (S3): the
  # machine-readable companion to eengine's .changes.yaml.
  #
  # Built from the Expressir::Changes::SchemaChange model (the same model
  # the .changes.yaml embodies), adding the classification dimension and a
  # rendered changelog.
  class ChangeManifest < Lutaml::Model::Serializable
    attribute :schema, :string
    attribute :version, :integer
    attribute :entries, ChangeEntry, collection: true

    yaml do
      map "schema", to: :schema
      map "version", to: :version
      map "entries", to: :entries
    end

    class << self
      # Build a manifest from a SchemaChange model.
      #
      # @param change [Expressir::Changes::SchemaChange]
      # @param version [Integer, String, nil] version to select
      #   (default: the latest)
      # @return [ChangeManifest]
      def from_schema_change(change, version: nil)
        selected = select_version(change.versions, version)
        return new(schema: change.schema) if selected.nil?

        new(
          schema: change.schema,
          version: selected.version,
          entries: entries_for(selected),
        )
      end

      # Build a manifest from a .changes.yaml file.
      #
      # @param path [String]
      # @param version [Integer, String, nil]
      # @return [ChangeManifest]
      def from_file(path, version: nil)
        from_schema_change(
          Expressir::Changes::SchemaChange.from_file(path),
          version: version,
        )
      end

      private

      def select_version(versions, version)
        return versions.last if version.nil?

        versions.find { |candidate| candidate.version == version.to_i }
      end

      def entries_for(version_change)
        entries = []
        entries.concat(item_entries(version_change.additions, "added"))
        entries.concat(item_entries(version_change.modifications, "modified"))
        entries.concat(item_entries(version_change.deletions, "removed"))
        entries.concat(mapping_entries(version_change.mappings))
        entries.concat(mapping_entries(version_change.changes))
        entries
      end

      def item_entries(items, action)
        Array(items).map do |item|
          ChangeEntry.new(
            element: item.name,
            element_type: item.type,
            action: action,
            classification: ChangeClassification.classify(action: action),
            description: Array(item.description),
          )
        end
      end

      def mapping_entries(mappings)
        Array(mappings).map do |mapping|
          ChangeEntry.new(
            element: mapping.name,
            element_type: "MAPPING",
            action: "mapping",
            classification: ChangeClassification::EDITORIAL,
            description: [mapping.description].compact,
          )
        end
      end
    end

    # Counts per classification.
    #
    # @return [Hash{String => Integer}]
    def summary
      entries.group_by(&:classification)
        .transform_values(&:size)
        .sort.to_h
    end

    # @return [Boolean]
    def breaking?
      entries.any? do |entry|
        entry.classification == ChangeClassification::BREAKING
      end
    end

    # Render a markdown changelog section.
    #
    # @return [String]
    def to_changelog
      lines = ["## Schema `#{schema}` — version #{version}", ""]
      entries.sort_by { |entry| [entry.classification, entry.element.to_s] }
        .each do |entry|
        lines << "- **#{entry.classification}** — #{entry.element_type} " \
                 "`#{entry.element}` #{entry.action}"
        Array(entry.description).each do |description|
          lines << "  - #{description}"
        end
      end
      lines.join("\n")
    end
  end
end
