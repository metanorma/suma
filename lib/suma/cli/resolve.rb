# frozen_string_literal: true

require "thor"

module Suma
  module Cli
    # Resolve command: emit canonical JSON + HTML artifacts for URNs.
    class Resolve < Thor
      def self.exit_on_failure?
        true
      end

      desc "resolve URN", "Resolve a URN to canonical JSON + HTML artifacts"
      option :manifest, type: :string, required: true,
                        desc: "Schema manifest used for schema/entity URNs"
      option :urn, type: :string,
                   desc: "Corpus URN base (defaults to the register URN)"
      option :concepts, type: :string,
                        desc: "Directory of Glossarist concept YAML files"
      option :register, type: :string,
                        desc: "Glossarist register.yaml (dataset URN)"
      option :output, type: :string, aliases: "-o", required: true,
                      desc: "Artifact output directory"
      option :all, type: :boolean, default: false,
                   desc: "Emit artifacts for every known URN"
      def resolve(urn = nil)
        resolver = UrnResolver.new(
          manifest_file: options[:manifest],
          urn: options[:urn],
          concepts_dir: options[:concepts],
          register_file: options[:register],
        )

        if options[:all]
          resolver.write(options[:output])
        elsif urn
          resolver.write_urn(urn, options[:output])
          Utils.log "Resolved #{urn}"
        else
          raise ArgumentError, "provide a URN or use --all"
        end
      end
    end
  end
end
