# frozen_string_literal: true

module Suma
  module SvgQuality
    # Simple report object wrapping svg_conform ValidationResult
    class Report
      attr_reader :file_path, :error_count, :errors

      def initialize(file_path, validation_result)
        @file_path = file_path
        @validation_result = validation_result
        @error_count = validation_result&.error_count || 0
        @errors = validation_result&.errors || []
      end

      def valid?
        @validation_result&.valid? || false
      end

      def quality_tier
        QualityTiers.for_error_count(@error_count)
      end

      def quality_score
        return 100 if @error_count.zero?
        return 0 if @error_count >= 200

        [100 - (@error_count * 0.5), 0].max.round
      end

      def errors_by_severity
        {
          critical: @errors.count { |e| e.requirement_id =~ /critical/i },
          high: @errors.count { |e| e.requirement_id =~ /high/i },
          medium: @errors.count { |e| e.requirement_id =~ /medium/i },
          low: @errors.count { |e| e.requirement_id =~ /low/i },
        }
      end

      def to_h
        {
          file_path: @file_path,
          valid: valid?,
          error_count: @error_count,
          quality_score: quality_score,
          quality_tier: quality_tier[:name],
          errors_by_severity: errors_by_severity,
        }
      end
    end
  end
end
