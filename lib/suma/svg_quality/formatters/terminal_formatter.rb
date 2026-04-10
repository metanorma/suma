# frozen_string_literal: true

require "pathname"

module Suma
  module SvgQuality
    module Formatters
      # Terminal output formatter with ASCII art and emojis
      class TerminalFormatter
        BORDER = "─"
        BOX_WIDTH = 80

        def initialize(batch_report, output: nil, sort: :quality)
          @batch_report = batch_report
          @output = output
          @sort = sort.to_sym
        end

        def format
          output_content = [
            header,
            "",
            summary_section,
            "",
            distribution_section,
            "",
            files_by_tier_section,
            "",
            footer,
          ].join("\n")

          write_output(output_content)
        end

        private

        attr_reader :batch_report

        def header
          sort_label = case @sort
                       when :errors then "error count (most first)"
                       else "quality score (lowest first)"
                       end

          "╔#{'═' * (BOX_WIDTH - 2)}╗\n" \
            "║  🔍 SVG Quality Report    Sorted by #{sort_label.ljust(33)}║\n" \
            "╚#{'═' * (BOX_WIDTH - 2)}╝"
        end

        def summary_section
          lines = []
          lines << "  📊 OVERVIEW"
          lines << ""
          lines << "    ● Total Files   : #{batch_report.total_files}"
          lines << "    ● Valid         : #{batch_report.successful} ✅"
          lines << "    ● Invalid      : #{batch_report.failed} ❌"
          lines << "    ● Avg Score    : #{batch_report.avg_quality_score.round(1)}/100"
          lines << "    ● Total Errors : #{batch_report.total_errors}"
          lines << "    ● Avg Errors   : #{batch_report.avg_error_count.round(1)}/file"
          lines << ""

          if (worst = batch_report.reports.first)
            tier = worst.quality_tier
            lines << "  🚨 WORST OFFENDER"
            lines << ""
            lines << "    #{tier[:emoji]} #{shorten_path(worst.file_path)}"
            lines << "    Score: #{worst.quality_score}/100 | Errors: #{worst.error_count} | #{tier[:name].to_s.upcase}"
          end

          lines.join("\n")
        end

        def distribution_section
          lines = []
          lines << "  📈 QUALITY DISTRIBUTION"
          lines << ""

          total = batch_report.total_files
          dist = batch_report.quality_distribution

          QualityTiers::ALL.each do |tier|
            count = dist[tier[:name].to_s].to_i
            pct = total.positive? ? (count.to_f / total * 100) : 0
            bar_len = (count.to_f / total * 40).round
            bar = bar_len.positive? ? "█" * bar_len : ""
            empty = "░" * (40 - bar_len)

            lines << "    #{tier[:emoji]} #{tier[:name].to_s.upcase.ljust(9)} #{bar}#{empty} #{count.to_s.rjust(4)} (#{sprintf(
              '%.1f', pct
            )}%)"
          end

          lines.join("\n")
        end

        def files_by_tier_section
          lines = []

          if @sort == :errors
            # When sorting by errors, show flat list (worst offenders first)
            lines << ""
            lines << "  📋 ALL FILES (sorted by error count, worst first)"
            lines << ""

            batch_report.reports.each do |report|
              lines << format_file_line(report)
            end
          else
            # When sorting by quality, group by tier - iterate CRITICAL first (worst first)
            reports_by_tier = batch_report.reports.group_by do |r|
              r.quality_tier[:name]
            end

            QualityTiers::ALL.each do |tier|
              tier_reports = reports_by_tier[tier[:name]]
              next unless tier_reports&.any?

              lines << ""
              lines << "  #{tier[:emoji]} #{tier[:name].to_s.upcase} QUALITY (#{tier_reports.size} files)"
              lines << ""

              tier_reports.each do |report|
                lines << format_file_line(report)
              end
            end
          end

          lines.join("\n")
        end

        def format_file_line(report)
          path = shorten_path(report.file_path)
          score = report.quality_score.to_i.to_s.rjust(3)
          errors = report.error_count.to_s.rjust(5)
          valid_str = report.valid? ? "✓" : "✗"

          "    #{valid_str} #{score}/100  #{errors} errors  #{path}"
        end

        def shorten_path(path)
          p = Pathname.new(path)
          if p.absolute?
            begin
              p.relative_path_from(Pathname.pwd)
            rescue StandardError
              p
            end
          else
            p
          end.to_s
        end

        def footer
          BORDER * BOX_WIDTH
        end

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
