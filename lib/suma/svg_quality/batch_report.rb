# frozen_string_literal: true

module Suma
  module SvgQuality
    # Batch report wrapping multiple SVG quality reports
    class BatchReport
      attr_reader :reports

      def initialize(reports)
        @reports = reports
      end

      def total_files
        @reports.size
      end

      def successful
        @reports.count(&:valid?)
      end

      def failed
        total_files - successful
      end

      def avg_quality_score
        return 0 if @reports.empty?

        @reports.sum(&:quality_score).to_f / total_files
      end

      def total_errors
        @reports.sum(&:error_count)
      end

      def avg_error_count
        return 0 if @reports.empty?

        total_errors.to_f / total_files
      end

      def quality_distribution
        dist = Hash.new(0)
        @reports.each do |r|
          dist[r.quality_tier[:name].to_s] += 1
        end
        dist
      end

      def sort_by_quality
        self.class.new(@reports.sort_by(&:quality_score))
      end

      def sort_by_errors
        self.class.new(@reports.sort_by { |r| -r.error_count })
      end

      def limit(count)
        return self if count.nil?

        self.class.new(@reports.first(count))
      end

      def filter_by_min_errors(min)
        return self if min.nil?

        self.class.new(@reports.select { |r| r.error_count >= min })
      end

      def to_json(*_args)
        JSON.pretty_generate(@reports.map(&:to_h))
      end

      def to_yaml
        YAML.dump(@reports.map(&:to_h))
      end
    end
  end
end
