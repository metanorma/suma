# frozen_string_literal: true

module Suma
  module Utils
    class << self
      attr_writer :output

      def output
        @output ||= $stderr
      end

      def log(message, level: :info)
        return if level == :debug && !ENV["SUMA_DEBUG"]

        output.puts "[suma] #{message}"
      end
    end
  end
end
