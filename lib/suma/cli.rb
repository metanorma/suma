# frozen_string_literal: true

module Suma
  module Cli
    autoload :Core,             "suma/cli/core"
    autoload :Build,            "suma/cli/build"
    autoload :CheckSvgQuality,  "suma/cli/check_svg_quality"
    autoload :Compare,          "suma/cli/compare"
    autoload :ConvertJsdai,     "suma/cli/convert_jsdai"
    autoload :Export,           "suma/cli/export"
    autoload :ExtractTerms,     "suma/cli/extract_terms"
    autoload :GenerateRegister, "suma/cli/generate_register"
    autoload :GenerateSchemas,  "suma/cli/generate_schemas"
    autoload :Reformat,         "suma/cli/reformat"
    autoload :Validate,         "suma/cli/validate"
    autoload :ValidateLinks,    "suma/cli/validate_links"
  end
end
