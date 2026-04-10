# frozen_string_literal: true

require "yaml"

module Suma
  module SvgQuality
    module Formatters
      # YAML output formatter
      class YamlFormatter
        def initialize(batch_report, output: nil)
          @batch_report = batch_report
          @output = output
        end

        def format
          write_output(@batch_report.to_yaml)
        end

        private

        def write_output(content)
          if @output
            File.write(@output, content)
            "[suma] Results written to #{@output}"
          else
            content
          end
        end
      end
    end
  end
end
