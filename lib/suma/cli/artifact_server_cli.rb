# frozen_string_literal: true

require "thor"

module Suma
  module Cli
    # Serve the emitted URN artifact tree with Accept negotiation.
    class ArtifactServerCli < Thor
      def self.exit_on_failure?
        true
      end

      desc "serve DIRECTORY", "Serve resolved URN artifacts locally"
      option :port, type: :numeric, default: ArtifactServer::DEFAULT_PORT,
                    desc: "TCP port to listen on"
      def serve(directory)
        Utils.log "Ctrl-C stops the server."
        ArtifactServer.new(directory, port: options[:port]).start
      end
    end
  end
end
