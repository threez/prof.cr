require "./sampler"
require "./resolver"
require "./location_resolver"
require "./report"

module Prof
  # High-level profiling API.
  #
  # ```
  # # Block form — preferred
  # report = Prof.profile(interval: 1.millisecond) { do_work }
  # report.to_speedscope("profile.json")
  #
  # # Manual start/stop
  # Prof.start(interval: 1.millisecond)
  # do_work
  # report = Prof.stop
  # puts report
  # ```
  class Profiler
    # Default maximum number of samples collected per run.
    DEFAULT_MAX_SAMPLES = 100_000
    # Default maximum call-stack depth captured per sample.
    DEFAULT_MAX_DEPTH = 64

    @@interval : Time::Span = 1.millisecond
    @@running = false

    # Starts the profiler, installing a `SIGPROF` handler and arming the
    # interval timer. Raises if the profiler is already running.
    #
    # - *interval*: sampling interval (CPU time). Clamped to a minimum of 1 µs;
    #   very short intervals increase overhead and saturate the buffer quickly.
    # - *max_samples*: hard cap on samples collected before the buffer is full.
    # - *max_depth*: maximum call-stack depth captured per sample.
    def self.start(
      interval : Time::Span = 1.millisecond,
      max_samples : Int32 = DEFAULT_MAX_SAMPLES,
      max_depth : Int32 = DEFAULT_MAX_DEPTH,
    ) : Nil
      raise "Profiler already running" if @@running
      @@interval = interval
      @@running = true
      interval_us = [interval.total_microseconds.to_i64, 1_i64].max
      begin
        Sampler.start(interval_us, max_samples, max_depth)
      rescue ex
        @@running = false
        raise ex
      end
    end

    # Stops the profiler, resolves captured addresses to `Frame` objects,
    # and returns a `Report`. Raises if the profiler is not running.
    def self.stop : Report
      raise "Profiler is not running" unless @@running
      @@running = false

      frames_buf, depths_buf, count, max_depth = Sampler.stop

      samples = begin
        Resolver.resolve(frames_buf, depths_buf, count, max_depth)
      ensure
        LibC.free(frames_buf.as(Void*))
        LibC.free(depths_buf.as(Void*))
      end

      locations = LocationResolver.resolve(samples)
      unless locations.empty?
        samples = samples.map do |stack|
          stack.map do |frame|
            if loc = locations[frame.address]?
              Frame.new(frame.address, frame.name, loc[0], loc[1])
            else
              frame
            end
          end
        end
      end

      Report.new(samples, @@interval)
    end

    # Profiles *block*, returning a `Report` with all collected samples.
    # The profiler is stopped automatically, even if *block* raises.
    def self.profile(
      interval : Time::Span = 1.millisecond,
      max_samples : Int32 = DEFAULT_MAX_SAMPLES,
      max_depth : Int32 = DEFAULT_MAX_DEPTH,
      &block
    ) : Report
      start(interval: interval, max_samples: max_samples, max_depth: max_depth)
      begin
        block.call
      rescue ex
        # Crystal discards the return value of `ensure` blocks, so `stop` must be
        # the final expression on the happy path. Swallow any stop error so the
        # original exception is always re-raised.
        stop rescue nil
        raise ex
      end
      stop
    end
  end
end
