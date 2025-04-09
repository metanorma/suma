module Suma
  module Util
    class WorkersPool
      def initialize(workers)
        @workers = workers
        @queue = SizedQueue.new(@workers)
        @mutex = Mutex.new
        @cv = ConditionVariable.new
        @pending_jobs = 0
        @threads = Array.new(@workers) { init_thread }
      end

      def init_thread
        Thread.new do
          catch(:exit) do
            loop do
              job, args = @queue.pop
              begin
                job.call(*args)
              rescue => e
                warn "Worker error: #{e.message}"
                warn e.backtrace.join("\n")
              ensure
                job_done
              end
            end
          end
        end
      end

      def schedule(*args, &block)
        job_scheduled
        @queue << [block, args]
      end

      def wait_all
        @mutex.synchronize do
          @cv.wait(@mutex) until @pending_jobs == 0
        end
      end

      def shutdown
        wait_all
        @workers.times { schedule { throw :exit } }
        @threads.map(&:join)
      end

      private

      def job_scheduled
        @mutex.synchronize { @pending_jobs += 1 }
      end

      def job_done
        @mutex.synchronize do
          @pending_jobs -= 1
          @cv.signal if @pending_jobs.zero?
        end
      end
    end
  end
end
