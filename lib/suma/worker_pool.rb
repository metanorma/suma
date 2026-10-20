# frozen_string_literal: true

module Suma
  # A bounded worker pool for independent per-schema work.
  #
  # Document compilation is deliberately excluded: Metanorma rendering is not
  # thread-safe and memory-hungry, so it stays sequential and composes with
  # StagedCollectionBuilder's process isolation. Parsing and file export are
  # independent per schema and safe to overlap.
  class WorkerPool
    attr_reader :size

    def initialize(size: 1)
      @size = Integer(size)
      raise ArgumentError, "worker pool size must be at least 1" if @size < 1
    end

    # Map +items+ in order, running at most +size+ blocks concurrently.
    #
    # @return [Array] results in input order
    def map(items, &block)
      return items.map(&block) if size == 1 || items.length <= 1

      queue = Queue.new
      items.each_with_index { |item, index| queue << [item, index] }
      results = Array.new(items.length)
      errors = Queue.new
      workers = Array.new([size, items.length].min) do
        worker(queue, results, errors, block)
      end
      workers.each(&:join)
      raise errors.pop unless errors.empty?

      results
    end

    private

    def worker(queue, results, errors, block)
      Thread.new do
        loop do
          pair = next_item(queue)
          break unless pair

          item, index = pair
          begin
            results[index] = block.call(item)
          rescue StandardError => e
            errors << e
            break
          end
        end
      end
    end

    def next_item(queue)
      queue.pop(true)
    rescue ThreadError
      nil
    end
  end
end
