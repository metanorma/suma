# frozen_string_literal: true

require "socket"

module Suma
  # Development server for the emitted URN artifact tree: serves the
  # static files at their URN-derived paths, negotiating JSON vs HTML by
  # the Accept header. Production hosting maps the same paths statically.
  class ArtifactServer
    DEFAULT_PORT = 2113

    attr_reader :directory, :port

    # @param directory [String] the resolve output directory
    # @param port [Integer] TCP port; 0 picks an ephemeral port
    def initialize(directory, port: DEFAULT_PORT)
      @directory = File.expand_path(directory)
      @port = port
    end

    # Resolve one HTTP request to a response.
    #
    # @param path [String] request path (with or without extension)
    # @param accept [String, nil] Accept header value
    # @return [Array(String, String, String)] status, content type, body
    def call(path, accept = nil)
      clean = path.to_s.split("?").first.to_s
      return not_found if clean.include?("..")

      clean = "/index.html" if clean.empty? || clean == "/"
      file = artifact_file(clean, accept)
      return not_found unless file

      ["200", content_type(file), File.read(file, encoding: "utf-8")]
    end

    # Handle a single connection (one HTTP request).
    def serve(socket)
      request = socket.gets&.strip
      return unless request

      accept = read_headers(socket)["accept"]
      status, type, body = call(request.split[1].to_s, accept)
      socket.write(
        "HTTP/1.1 #{status} #{status_name(status)}\r\n" \
        "Content-Type: #{type}\r\nContent-Length: #{body.bytesize}\r\n" \
        "Connection: close\r\n\r\n#{body}",
      )
    ensure
      socket&.close
    end

    # Accept connections until interrupted.
    def start
      server = TCPServer.new("localhost", @port)
      @port = server.addr[1]
      Utils.log "Serving #{@directory} at http://localhost:#{@port}"
      loop { serve(server.accept) }
    ensure
      server&.close
    end

    private

    def read_headers(socket)
      headers = {}
      while (line = socket.gets) && line != "\r\n" && !line.strip.empty?
        key, value = line.split(":", 2)
        headers[key.strip.downcase] = value.strip if value
      end
      headers
    end

    def artifact_file(clean, accept)
      base = clean.delete_prefix("/")
      candidates = if base.end_with?(".json", ".html")
                     [base]
                   else
                     wants_json = accept.to_s.include?("application/json")
                     ["#{base}.#{wants_json ? 'json' : 'html'}"]
                   end
      candidates.map { |candidate| File.join(@directory, candidate) }
        .find { |file| File.file?(file) }
    end

    def content_type(file)
      if file.end_with?(".json")
        "application/json"
      else
        "text/html; charset=utf-8"
      end
    end

    def not_found
      ["404", "text/plain", "not found\n"]
    end

    def status_name(status)
      status == "200" ? "OK" : "Not Found"
    end
  end
end
