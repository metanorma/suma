# frozen_string_literal: true

require "pathname"

module Suma
  module Cli
    # Check SVG quality. Thin adapter around +Suma::SvgQuality::Scanner+:
    # argument parsing, file discovery, sorting, filtering, output
    # formatting. The deep scanner module owns validation orchestration
    # and is reachable from specs without invoking Thor.
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
        show_progress = options[:progress] || ($stdout.tty? && !options[:output])
        sync_stdio! if show_progress

        files = discover_files(path_obj)
        return if files.empty?

        if single_file?(path_obj, files)
          print_single_report(scan_single(files.first))
        else
          scan_and_output(files, show_progress)
        end
      end

      private

      attr_reader :options

      def single_file?(path_obj, files)
        path_obj.file? && files.size == 1
      end

      def scan_and_output(files, show_progress)
        puts "🔍 Scanning #{files.size} SVG files..." if show_progress
        batch = SvgQuality::Scanner.new(
          profile: options[:profile],
          progress: progress_adapter(show_progress),
        ).scan(files)
        output_report(sort_report(batch))
      end

      def sync_stdio!
        $stdout.sync = true
        $stderr.sync = true
      end

      def discover_files(path)
        if path.directory?
          Pathname.glob(path.join(options[:pattern])).select(&:file?)
        elsif path.file? && path.extname == ".svg"
          [path]
        else
          []
        end
      end

      def scan_single(path)
        SvgQuality::Scanner.new(profile: options[:profile]).scan_file(path)
      end

      def print_single_report(report)
        result = report
        puts "📄 SVG Quality Report: #{result.file_path}"
        puts ""
        puts "  Valid: #{result.valid? ? 'YES ✅' : 'NO ❌'}"
        puts "  Errors: #{result.error_count}"
        puts ""

        return unless result.errors.any?

        puts "  📋 Error Details"
        puts ""
        by_req = result.errors.group_by(&:requirement_id)
        by_req.each do |req_id, errors|
          puts "  #{req_id} (#{errors.size} occurrences)"
          errors.first(5).each { |e| puts "    - #{e.message}" }
          puts "    ... and #{errors.size - 5} more" if errors.size > 5
          puts ""
        end
      end

      def progress_adapter(enabled)
        return SvgQuality::Scanner::NullProgress.new unless enabled

        ->(_index, _total, report) do
          tier = report.quality_tier
          status = report.valid? ? "✅" : "❌"
          $stderr.print "  #{tier[:emoji]} #{report.error_count} errors " \
                        "#{status} #{shorten_path(report.file_path)}\n"
          $stderr.flush
        end
      end

      def sort_report(batch_report)
        case options[:sort]
        when :quality then batch_report.sort_by_quality
        else batch_report.sort_by_errors
        end
      end

      def output_report(batch_report)
        filtered = batch_report.filter_by_min_errors(options[:min_errors])
        limited = filtered.limit(options[:limit])

        formatter = formatter_for(limited)
        puts formatter.format
      end

      def formatter_for(batch_report)
        case options[:format].to_sym
        when :json
          SvgQuality::Formatters::JsonFormatter.new(batch_report,
                                                    output: options[:output])
        when :yaml
          SvgQuality::Formatters::YamlFormatter.new(batch_report,
                                                    output: options[:output])
        else
          SvgQuality::Formatters::TerminalFormatter.new(batch_report,
                                                        output: options[:output],
                                                        sort: options[:sort])
        end
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
