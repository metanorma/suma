# frozen_string_literal: true

module Suma
  # Reformats EXPRESS source into suma's canonical form: comment blocks
  # (the +(*"...\n*)+ remarks that EXPRESS uses for documentation) are
  # extracted from their inline positions and appended to the end of
  # the file, and excess blank lines are collapsed.
  #
  # Pure content transformation — no I/O, no Thor, no filesystem. The
  # CLI adapter handles reading from and writing to disk.
  #
  # The transform is idempotent: reformatting an already-reformatted
  # document returns +changed?: false+.
  #
  # Comment extraction uses +String#index+ rather than a single m-mode
  # regex. The original +/\(\*"(.*?)\n\*\)/m+ is correct functionally
  # but is polynomial-time on adversarial input (CodeQL
  # +rb/polynomial-redos+). Scanning for the start marker, then for
  # the next terminator, is unambiguously linear.
  module ExpressReformatter
    Result = Struct.new(:content, :changed?, keyword_init: true) do
      def content_or_nil
        changed? ? content : nil
      end
    end

    COMMENT_START = '(*"'
    COMMENT_END = "\n*)"
    BLANK_RUN_PATTERN = /(\n\n+)/
    NEWLINE_RUN_PATTERN = /(\n+)/

    module_function

    def call(content)
      comments = extract_comments(content)
      return Result.new(content: content, changed?: false) if comments.empty?

      without_comments = strip_comments(content)
      new_comments = comments.map { |c| "#{COMMENT_START}#{c}#{COMMENT_END}" }
        .join("\n\n")
      new_content = "#{without_comments}\n\n#{new_comments}\n"
      new_content = new_content.gsub(BLANK_RUN_PATTERN, "\n\n")

      changed = normalised_compare(content, new_content) != 0
      Result.new(content: new_content, changed?: changed)
    end

    def extract_comments(content)
      comments = []
      pos = 0
      while (start_idx = content.index(COMMENT_START, pos))
        end_idx = content.index(COMMENT_END, start_idx + COMMENT_START.length)
        break unless end_idx

        comments << content[(start_idx + COMMENT_START.length)...end_idx]
        pos = end_idx + COMMENT_END.length
      end
      comments
    end

    def strip_comments(content)
      return content unless content.index(COMMENT_START, 0)

      stripped = +""
      last_end = 0
      each_comment_range(content) do |range|
        stripped << content[range[:pre_start]...range[:start]]
        last_end = range[:end_exclusive]
      end
      stripped << content[last_end..]
      stripped.force_encoding(content.encoding)
    end

    def each_comment_range(content)
      return enum_for(:each_comment_range, content) unless block_given?

      pos = 0
      while (start_idx = content.index(COMMENT_START, pos))
        end_idx = content.index(COMMENT_END, start_idx + COMMENT_START.length)
        break unless end_idx

        yield pre_start: pos, start: start_idx,
              end_exclusive: end_idx + COMMENT_END.length
        pos = end_idx + COMMENT_END.length
      end
    end

    def normalised_compare(left, right)
      left.gsub(NEWLINE_RUN_PATTERN, "\n") <=> right.gsub(NEWLINE_RUN_PATTERN, "\n")
    end

    private_class_method :normalised_compare
  end
end
