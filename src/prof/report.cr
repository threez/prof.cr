require "./frame"
require "./output/speedscope"
require "./output/folded"

module Prof
  # The result of a profiling run: captured call stacks plus metadata.
  #
  # Obtain a `Report` from `Prof.profile` or `Prof.stop`. Inspect samples
  # directly or export them with `to_speedscope` / `to_folded`.
  class Report
    # All captured call stacks. Each inner array is one sample, with the
    # innermost (leaf/hottest) frame first and the outermost (root) frame last.
    getter samples : Array(Array(Frame))

    # Sampling interval used during the run.
    getter interval : Time::Span

    def initialize(@samples : Array(Array(Frame)), @interval : Time::Span)
    end

    # Total number of samples captured (equals `samples.size`).
    def total_samples : Int32
      @samples.size
    end

    # ── Output helpers ──────────────────────────────────────────────────────

    # Writes the profile as a [speedscope](https://www.speedscope.app) sampled-
    # profile JSON to *io*. Use *name* to label the profile in the UI.
    def to_speedscope(io : IO, name : String = "CPU Profile") : Nil
      Output::Speedscope.write(io, @samples, @interval, name)
    end

    # Writes the profile as a speedscope sampled-profile JSON to *path*.
    def to_speedscope(path : String, name : String = "CPU Profile") : Nil
      File.open(path, "w") { |file_io| to_speedscope(file_io, name) }
    end

    # Writes the profile in folded-stacks format to *io*.
    # Compatible with `flamegraph.pl` and speedscope import.
    def to_folded(io : IO) : Nil
      Output::Folded.write(io, @samples)
    end

    # Writes the profile in folded-stacks format to *path*.
    def to_folded(path : String) : Nil
      File.open(path, "w") { |file_io| to_folded(file_io) }
    end

    # ── Convenience analysis ────────────────────────────────────────────────

    # Returns the *n* hottest frames by sample count, sorted descending.
    # "Hottest" is the innermost (leaf) frame of each sample stack.
    # Multiple samples with the same frame name are aggregated; the representative
    # frame shown is the one with source location info, if any.
    def top(n : Int32 = 10) : Array({Frame, Int32})
      counts = Hash(String, {Frame, Int32}).new
      @samples.each do |stack|
        next if stack.empty?
        leaf = stack.first
        if entry = counts[leaf.name]?
          best = entry[0].file ? entry[0] : leaf
          counts[leaf.name] = {best, entry[1] + 1}
        else
          counts[leaf.name] = {leaf, 1}
        end
      end
      counts.values.sort_by! { |_, count| -count }.first(n)
    end

    # Prints a text summary showing the top-10 hottest frames with sample
    # counts and percentages.
    def to_s(io : IO) : Nil
      io << "Prof::Report — #{total_samples} samples @ #{@interval}\n"
      top(10).each_with_index do |(frame, count), i|
        pct = (count * 100.0 / total_samples).round(1)
        loc = if f = frame.file
                "  #{File.basename(f)}:#{frame.line}"
              else
                ""
              end
        io << "  #{(i + 1).to_s.rjust(2)}. #{pct.to_s.rjust(5)}%  #{frame.name}#{loc}\n"
      end
    end
  end
end
