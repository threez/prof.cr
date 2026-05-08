module Prof
  # A single stack frame captured during a profiling run.
  struct Frame
    # Raw instruction-pointer address of this frame.
    getter address : UInt64
    # Resolved symbol name (mangled Crystal name from `backtrace_symbols` or `dladdr`).
    getter name : String
    # Source file path resolved from DWARF debug info (`nil` when not available).
    getter file : String?
    # Source line number resolved from DWARF debug info (`nil` when not available).
    getter line : Int32?

    def initialize(@address : UInt64, @name : String,
                   @file : String? = nil, @line : Int32? = nil)
    end

    # Formats as `"name @ basename:line"` when location info is present,
    # `"name @ basename"` when only the file is known, or just `"name"`.
    def to_s(io : IO) : Nil
      io << name
      if f = @file
        io << " @ " << File.basename(f)
        io << ':' << @line if @line
      end
    end

    # Returns `"file:line"` when both are known, `"file"` when only the file
    # is known, or `nil` when no source location is available.
    def location : String?
      return nil unless f = @file
      l = @line
      l ? "#{f}:#{l}" : f
    end
  end
end
