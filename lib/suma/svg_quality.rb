# frozen_string_literal: true

require "svg_conform"

module Suma
  module SvgQuality
    autoload :Report,      "suma/svg_quality/report"
    autoload :BatchReport, "suma/svg_quality/batch_report"

    module QualityTiers
      CRITICAL = { name: :critical, min_errors: 200, emoji: "💥" }.freeze
      HIGH = { name: :high, min_errors: 100, emoji: "🔴" }.freeze
      MEDIUM = { name: :medium, min_errors: 50, emoji: "⚠️" }.freeze
      LOW = { name: :low, min_errors: 20, emoji: "🔶" }.freeze
      MINOR = { name: :minor, min_errors: 0, emoji: "✅" }.freeze

      ALL = [CRITICAL, HIGH, MEDIUM, LOW, MINOR].freeze

      def self.for_error_count(count)
        ALL.find { |tier| count >= tier[:min_errors] } || MINOR
      end
    end

    class << self
      def validator(profile: :svg_1_2_rfc)
        SvgConform::Validator.new
      end
    end
  end
end
