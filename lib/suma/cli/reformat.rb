# frozen_string_literal: true

require "thor"

module Suma
  module Cli
    # Reformat command for reformatting EXPRESS files.
    #
    # Thin Thor adapter around Suma::ExpressReformatter: argument
    # parsing, file discovery, and read/transform/write. The content
    # transformation itself lives in the deep module and is tested
    # independently.
    class Reformat < Thor
      desc "reformat EXPRESS_FILE_PATH", "Reformat EXPRESS files"
      option :recursive, type: :boolean, default: false, aliases: "-r",
                         desc: "Reformat EXPRESS files under the specified " \
                               "path recursively"

      def reformat(express_file_path)
        files = discover_files(express_file_path)
        ensure_files_found!(files, express_file_path)
        process_files(files)
      end

      private

      def discover_files(path)
        return [path] if File.file?(path)
        return Dir.glob("#{path}/**/*.exp") if options[:recursive]

        Dir.glob("#{path}/*.exp")
      end

      def ensure_files_found!(files, path)
        if File.file?(path)
          unless File.extname(path) == ".exp"
            raise ArgumentError,
                  "Specified file `#{path}` is not an EXPRESS file."
          end
        elsif !File.exist?(path)
          raise Errno::ENOENT,
                "Specified EXPRESS file `#{path}` not found."
        end
        return unless files.empty?

        raise Errno::ENOENT, "No EXPRESS files found in `#{path}`."
      end

      def process_files(files)
        files.each { |file| reformat_one(file) }
      end

      def reformat_one(file)
        result = ExpressReformatter.call(File.read(file))
        if result.changed?
          File.write(file, result.content)
          puts "Reformatted EXPRESS file and saved to #{file}"
        else
          puts "No changes made to #{file}"
        end
      end
    end
  end
end
