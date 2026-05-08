require "./prof/profiler"
require "./prof/report"

# A sampling CPU profiler for Crystal programs.
#
# Installs a SIGPROF handler via `sigaction(2)` and fires it on a
# CPU-time interval set with `setitimer(2)`. Each signal captures the
# current call stack with `backtrace(3)` into a pre-allocated buffer.
# After `stop`, addresses are resolved to symbol names with
# `backtrace_symbols(3)` (Darwin / Linux glibc) or `dladdr(3)` (FreeBSD / others)
# and the result is wrapped in a `Prof::Report`.
#
# The report can be emitted as speedscope JSON or folded stacks
# (flamegraph.pl / speedscope import).
#
# ```
# report = Prof.profile(interval: 1.millisecond) do
#   compute_something_expensive
# end
# report.to_speedscope("profile.json")
# puts report # prints top-10 hottest frames
# ```
module Prof
  VERSION = "0.1.0"

  # Starts the profiler. See `Profiler.start` for parameter documentation.
  # Raises if the profiler is already running.
  def self.start(**opts) : Nil
    Profiler.start(**opts)
  end

  # Stops the profiler and returns the collected `Report`.
  # Raises if the profiler is not running.
  def self.stop : Report
    Profiler.stop
  end

  # Profiles *block*, collecting CPU samples at the given *interval*,
  # and returns a `Report` with all captured stacks.
  # The profiler is stopped automatically, even if *block* raises.
  def self.profile(**opts, &block) : Report
    Profiler.profile(**opts, &block)
  end
end
