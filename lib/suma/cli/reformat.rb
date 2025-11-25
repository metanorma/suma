# frozen_string_literal: true

require "thor"
require_relative "../thor_ext"

module Suma
  module Cli
    # Reformat command for reformatting EXPRESS files
    class Reformat < Thor
      desc "reformat EXPRESS_FILE_PATH",
           "Reformat EXPRESS files"
      option :recursive, type: :boolean, default: false, aliases: "-r",
                         desc: "Reformat EXPRESS files under the specified " \
                               "path recursively"

      def reformat(express_file_path) # rubocop:disable Metrics/AbcSize
        if File.file?(express_file_path)
          unless File.exist?(express_file_path)
            raise Errno::ENOENT, "Specified EXPRESS file " \
                                 "`#{express_file_path}` not found."
          end

          if File.extname(express_file_path) != ".exp"
            raise ArgumentError, "Specified file `#{express_file_path}` is " \
                                 "not an EXPRESS file."
          end

          exp_files = [express_file_path]
        elsif options[:recursive]
          exp_files = Dir.glob("#{express_file_path}/**/*.exp")
        else
          exp_files = Dir.glob("#{express_file_path}/*.exp")
        end

        if exp_files.empty?
          raise Errno::ENOENT, "No EXPRESS files found in " \
                               "`#{express_file_path}`."
        end

        run(exp_files)
      end

      private

      def run(exp_files)
        exp_files.each do |exp_file|
          reformat_exp(exp_file)
        end
      end

      def reformat_exp(file) # rubocop:disable Metrics/AbcSize
        # Read the file content
        file_content = File.read(file)

        # Extract all comments between '(*"' and '\n*)'
        # Avoid incorrect selection of some comment blocks
        # containing '(*text*)' inside
        comments = file_content.scan(/\(\*"(.*?)\n\*\)/m).map(&:first)

        if comments.any?
          content_without_comments = file_content.gsub(/\(\*".*?\n\*\)/m, "")

          # remove extra newlines
          new_content = content_without_comments.gsub(/(\n\n+)/, "\n\n")
          # Add '(*"' and '\n*)' to enclose the comment block
          new_comments = comments.map { |c| "(*\"#{c}\n*)" }.join("\n\n")
          # Append the comments to the end of the file
          new_content = "#{new_content}\n\n#{new_comments}\n"

          # Compare the changes between the original content with the modified
          # content, if the changes are just whitespaces, skip modifying the
          # file
          if file_content.gsub(/(\n+)/, "\n") == new_content.gsub(/(\n+)/, "\n")
            puts "No changes made to #{file}"
            return
          end

          update_exp(file, new_content)
        end
      end

      def update_exp(file, content)
        # Write the modified content to a new file
        File.write(file, content)
        puts "Reformatted EXPRESS file and saved to #{file}"
      end
    end
  end
end
