# frozen_string_literal: true

require "thor"

module Suma
  module Cli
    # Package extracted concepts into a GCR archive for the Vocabulary
    # Browser.
    class PackageGcr < Thor
      def self.exit_on_failure?
        true
      end

      desc "package_gcr CONCEPTS_DIR",
           "Package extracted Glossarist concepts into a .gcr archive"
      option :register, type: :string, required: true,
                        desc: "register.yaml (dataset identity)"
      option :shortname, type: :string, required: true,
                         desc: "Dataset id (matches datasets.yml `id`)"
      option :version, type: :string, required: true,
                       desc: "Semver of this dataset release"
      option :title, type: :string, required: true,
                     desc: "Human-readable dataset title"
      option :description, type: :string, required: true,
                           desc: "Dataset description"
      option :created_at, type: :string,
                          desc: "Package timestamp (ISO 8601); pin for " \
                                "reproducible archives"
      option :output, type: :string, aliases: "-o", required: true,
                      desc: "Output directory for the .gcr archives"

      def package_gcr(concepts_dir)
        GcrPackage.new(
          concepts_dir: concepts_dir,
          register_file: options[:register],
          shortname: options[:shortname],
          version: options[:version],
          title: options[:title],
          description: options[:description],
          created_at: pinned_time,
        ).write(options[:output])
      end

      private

      def pinned_time
        options[:created_at] && Time.iso8601(options[:created_at])
      end
    end
  end
end
