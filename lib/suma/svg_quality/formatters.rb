# frozen_string_literal: true

module Suma
  module SvgQuality
    module Formatters
      autoload :TerminalFormatter,
               "suma/svg_quality/formatters/terminal_formatter"
      autoload :JsonFormatter,     "suma/svg_quality/formatters/json_formatter"
      autoload :YamlFormatter,     "suma/svg_quality/formatters/yaml_formatter"
    end
  end
end
