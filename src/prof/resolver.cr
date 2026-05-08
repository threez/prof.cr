require "./frame"
require "c/dlfcn"
{% if flag?(:darwin) || flag?(:linux) %}
  require "./c/execinfo"
{% end %}

module Prof
  # :nodoc:
  module Resolver
    {% if flag?(:darwin) || flag?(:linux) %}
      SKIP = 3 # backtrace() itself + signal handler + OS trampoline
    {% else %}
      SKIP = 2 # signal handler + OS trampoline (libunwind starts inside the handler)
    {% end %}

    def self.resolve(
      frames_buf : UInt64*,
      depths_buf : Int32*,
      count : Int32,
      max_depth : Int32,
      skip : Int32 = SKIP,
    ) : Array(Array(Frame))
      {% if flag?(:darwin) || flag?(:linux) %}
        # First pass: collect unique addresses for a single batch backtrace_symbols
        # call instead of one call per sample (O(samples) → O(unique_addresses)).
        ordered_addrs = [] of UInt64
        addr_seen = Set(UInt64).new
        each_address(frames_buf, depths_buf, count, max_depth, skip) do |addr|
          unless addr_seen.includes?(addr)
            addr_seen << addr
            ordered_addrs << addr
          end
        end

        name_map = Hash(UInt64, String).new(initial_capacity: ordered_addrs.size)
        unless ordered_addrs.empty?
          syms = LibExecinfo.backtrace_symbols(
            ordered_addrs.to_unsafe.as(Pointer(Pointer(Void))),
            ordered_addrs.size
          )
          ordered_addrs.each_with_index do |addr, i|
            ptr = syms ? syms[i] : Pointer(UInt8).null
            name_map[addr] = ptr.null? ? "0x#{addr.to_s(16)}" : clean_name(String.new(ptr))
          end
          LibC.free(syms.as(Void*)) if syms
        end

        # Second pass: build Frame arrays using the pre-resolved names.
        build_samples(frames_buf, depths_buf, count, max_depth, skip) do |addr|
          Frame.new(addr, name_map[addr]? || "0x#{addr.to_s(16)}")
        end
      {% else %}
        build_samples(frames_buf, depths_buf, count, max_depth, skip) do |addr|
          Frame.new(addr, resolve_via_dladdr(addr))
        end
      {% end %}
    end

    # Iterates over every captured address across all samples, skipping profiler
    # frames, and yields each address to the block.
    private def self.each_address(
      frames_buf : UInt64*,
      depths_buf : Int32*,
      count : Int32,
      max_depth : Int32,
      skip : Int32,
      & : UInt64 ->
    ) : Nil
      count.times do |i|
        raw_depth = depths_buf[i]
        ns = [skip, raw_depth].min
        rd = raw_depth - ns
        next if rd <= 0
        slot = frames_buf + i.to_i64 * max_depth
        rd.times do |j|
          yield (slot + ns + j).value
        end
      end
    end

    # Builds one Array(Frame) per sample by calling the block for each address.
    private def self.build_samples(
      frames_buf : UInt64*,
      depths_buf : Int32*,
      count : Int32,
      max_depth : Int32,
      skip : Int32,
      & : UInt64 -> Frame
    ) : Array(Array(Frame))
      samples = Array(Array(Frame)).new(count)
      count.times do |i|
        raw_depth = depths_buf[i]
        ns = [skip, raw_depth].min
        rd = raw_depth - ns
        next if rd <= 0
        slot = frames_buf + i.to_i64 * max_depth
        frames = Array(Frame).new(rd)
        rd.times do |j|
          frames << yield (slot + ns + j).value
        end
        samples << frames
      end
      samples
    end

    # Strip the leading columns from backtrace_symbols output and the trailing
    # instruction offset so all samples at different sites within the same
    # function are merged under one name.
    #
    # macOS: "N   binary   0xADDR   sym + offset"  → "sym"
    # Linux: "binary(sym+0xOFF) [0xADDR]"          → "sym"
    #
    # Crystal symbol names contain parentheses (e.g. *Pointer(Bool)), so the
    # Linux format is parsed by finding the first "(" and the last ") [" rather
    # than with a greedy [^)]* pattern.
    {% if flag?(:darwin) || flag?(:linux) %}
      def self.clean_name(raw : String) : String
        name = if raw =~ /^\d+\s+\S+\s+0x\S+\s+(.+)$/
                 # macOS: strip leading columns
                 $~[1]
               elsif raw.ends_with?("]") && (bi = raw.rindex(" ["))
                 # Linux: strip " [0xADDR]" suffix then extract symbol from parens.
                 # The symbol section is "binary(sym+0xOFF)" — find the first "("
                 # which separates the binary path from the symbol.
                 without_addr = raw[0...bi]
                 if (po = without_addr.index("(")) && without_addr.ends_with?(")")
                   without_addr[po + 1...-1]
                 else
                   raw.strip
                 end
               else
                 raw.strip
               end
        # Drop any trailing offset: "+0xHEX", "+0x0", "+0" (decimal), or " + N".
        cleaned = name
          .sub(/\+0x[0-9a-f]+$/i, "")
          .sub(/\+\d+$/, "")
          .sub(/\s+\+\s+\d+$/, "")
          .strip
        # When backtrace_symbols has no symbol it emits "binary(+0xOFF)" which strips
        # to "".  Fall back to the raw string so the frame name is never blank.
        cleaned.empty? ? raw.strip : cleaned
      end
    {% end %}

    # Resolve a single address to a symbol name using dladdr(3).
    # The offset is omitted so all instruction sites in the same function share
    # one name and are aggregated together in top / speedscope / folded output.
    {% unless flag?(:darwin) %}
      private def self.resolve_via_dladdr(addr : UInt64) : String
        info = uninitialized LibC::DlInfo
        if LibC.dladdr(Pointer(Void).new(addr), pointerof(info)) != 0 && !info.dli_sname.null?
          String.new(info.dli_sname)
        else
          "0x#{addr.to_s(16)}"
        end
      end
    {% end %}
  end
end
