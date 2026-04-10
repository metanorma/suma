# frozen_string_literal: true

require "pathname"
require_relative "../svg_quality"
require_relative "../svg_quality/report"
require_relative "../svg_quality/batch_report"
require_relative "../svg_quality/formatters/terminal_formatter"
require_relative "../svg_quality/formatters/json_formatter"
require_relative "../svg_quality/formatters/yaml_formatter"

module Suma
  module Cli
    # Check SVG quality using svg_conform Validator API - thin CLI wrapper
    class CheckSvgQuality
      DATA_PATH = "schemas"
      DEFAULT_PATTERN = "**/*.svg"
      DEFAULT_PROFILE = :metanorma

      def initialize(pattern: DEFAULT_PATTERN, profile: DEFAULT_PROFILE,
                    format: "terminal", output: nil, min_errors: nil,
                    summary_only: false, progress: false, limit: nil,
                    sort: "errors")
        @options = {
          pattern: pattern,
          profile: profile,
          format: format,
          output: output,
          min_errors: min_errors,
          summary_only: summary_only,
          progress: progress,
          limit: limit,
          sort: sort.to_sym,
        }
      end

      def run(path = DATA_PATH)
        require "svg_conform"

        path_obj = Pathname.new(path).expand_path

        # Enable progress by default when outputting to terminal
        show_progress = options[:progress] || ($stdout.tty? && !options[:output])
        if show_progress
          $stdout.sync = true
          $stderr.sync = true
        end

        if path_obj.file?
          # Single file mode - show detailed errors
          analyze_single_file(path_obj)
        else
          # Directory mode - show batch report
          svg_files = find_svg_files(path_obj)

          if svg_files.empty?
            puts "No SVG files found in #{path}"
            return
          end

          puts "🔍 Scanning #{svg_files.size} SVG files..."
          puts

          reports = analyze_files_one_by_one(svg_files, show_progress)
          batch_report = SvgQuality::BatchReport.new(reports)
          sorted_report = sort_report(batch_report)
          output_report(sorted_report)
        end
      end

      def analyze_single_file(path)
        validator = SvgConform::Validator.new
        result = validator.validate_file(path.to_s, profile: options[:profile])

        puts "📄 SVG Quality Report: #{path}"
        puts ""
        puts "  Valid: #{result.valid? ? 'YES ✅' : 'NO ❌'}"
        puts "  Errors: #{result.error_count}"
        puts ""

        if result.errors.any?
          puts "  📋 Error Details"
          puts ""

          # Group errors by requirement_id
          by_req = result.errors.group_by(&:requirement_id)

          by_req.each do |req_id, errors|
            puts "  #{req_id} (#{errors.size} occurrences)"
            errors.first(5).each do |e|
              puts "    - #{e.message}"
            end
            if errors.size > 5
              puts "    ... and #{errors.size - 5} more"
            end
            puts ""
          end
        end
      end

      private

      attr_reader :options

      def find_svg_files(path)
        if path.directory?
          Pathname.glob(path.join(options[:pattern])).select(&:file?)
        elsif path.file? && path.extname == ".svg"
          [path]
        else
          []
        end
      end

      def analyze_files_one_by_one(files, show_progress = false)
        validator = SvgConform::Validator.new
        reports = []

        files.each_with_index do |file, index|
          result = validator.validate_file(file.to_s,
                                           profile: options[:profile])
          report = SvgQuality::Report.new(file.to_s, result)
          reports << report

          if show_progress
            tier = report.quality_tier
            status = report.valid? ? "✅" : "❌"
            msg = "  [#{index + 1}/#{files.size}] #{tier[:emoji]} #{report.error_count} errors #{status} #{shorten_path(file)}\n"
            $stderr.print msg
            $stderr.flush
          end
        end

        reports
      end

      def sort_report(batch_report)
        case options[:sort]
        when :quality
          batch_report.sort_by_quality
        else
          batch_report.sort_by_errors
        end
      end

      def output_report(batch_report)
        filtered = batch_report.filter_by_min_errors(options[:min_errors])
        limited = filtered.limit(options[:limit])

        formatter = case options[:format].to_sym
                    when :json
                      SvgQuality::Formatters::JsonFormatter.new(limited,
                                                                output: options[:output])
                    when :yaml
                      SvgQuality::Formatters::YamlFormatter.new(limited,
                                                                output: options[:output])
                    else
                      SvgQuality::Formatters::TerminalFormatter.new(limited,
                                                                    output: options[:output], sort: options[:sort])
                    end

        puts formatter.format
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
    end
  end
end
