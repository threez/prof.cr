require "./frame"
require "c/dlfcn"

module Prof
  # :nodoc:
  module LocationResolver
    # Maximum number of addresses passed to addr2line in a single invocation.
    # Keeps the argument list well under ARG_MAX (typically 2 MB on Linux).
    ADDR2LINE_BATCH = 4096

    # Returns a hash mapping address → {file, line} for every address in
    # *samples* that addr2line can resolve.  Addresses with no debug info are
    # omitted from the result.  Returns an empty hash if addr2line is not on
    # PATH or the binary has no DWARF info.
    def self.resolve(samples : Array(Array(Frame))) : Hash(UInt64, {String, Int32})
      result = Hash(UInt64, {String, Int32}).new

      binary = self_exe
      return result unless binary && addr2line_available?

      addrs = samples.each_with_object(Set(UInt64).new) do |stack, set|
        stack.each { |frame| set << frame.address }
      end
      return result if addrs.empty?

      # Determine the binary's load base so we can convert runtime addresses to
      # the file-relative virtual addresses that addr2line expects.  We pass a
      # known in-binary address (a pointer to this very method) so dladdr is
      # certain to return the main executable's dli_fbase and not a .so base.
      # Returns nil if dladdr fails; skip resolution rather than pass wrong addresses.
      load_base = self_load_base
      return result unless load_base

      # Process in batches to avoid hitting ARG_MAX with large address sets.
      addrs.each_slice(ADDR2LINE_BATCH) do |batch|
        hex_batch = batch.map { |addr| addr < load_base ? "0x0" : "0x#{(addr - load_base).to_s(16)}" }

        output = IO::Memory.new
        status = Process.run(
          "addr2line",
          args: ["-e", binary, "-f", "-C", "--"] + hex_batch,
          output: output,
          error: Process::Redirect::Close
        )
        next unless status.success?

        lines = output.to_s.lines
        batch.each_with_index do |addr, i|
          # addr2line emits two lines per address: function name, then file:line
          func_line = lines[i * 2]?
          loc_line = lines[i * 2 + 1]?
          next unless func_line && loc_line

          loc = loc_line.strip
          next if loc.starts_with?("??")

          colon = loc.rindex(':')
          next unless colon

          file = loc[0...colon]
          line = loc[colon + 1..].to_i?
          next unless line && line > 0

          result[addr] = {file, line}
        end
      end

      result
    end

    # Returns the runtime load base of the main executable.
    # Uses a class variable (guaranteed to reside in the main binary's .bss)
    # as the anchor address for dladdr so dli_fbase is the executable's ASLR
    # base and not the base of a dynamically-loaded shared library.
    # For PIE binaries: file_virtual_address = runtime_address - load_base.
    @@_anchor : UInt8 = 0_u8

    private def self.self_load_base : UInt64?
      info = uninitialized LibC::DlInfo
      anchor_ptr = pointerof(@@_anchor).as(Void*)
      return nil if LibC.dladdr(anchor_ptr, pointerof(info)) == 0
      info.dli_fbase.address
    end

    private def self.self_exe : String?
      {% if flag?(:linux) %}
        # crystal run deletes the temp binary after exec'ing it, so File.realpath
        # returns a path that no longer exists on the filesystem.
        # /proc/<pid>/exe is a per-process symlink the kernel maintains to the
        # executable inode even after the directory entry is removed.
        # We must use the PID-specific path because /proc/self/exe in a child
        # process refers to that child's binary, not ours.
        path = "/proc/#{Process.pid}/exe"
        File.symlink?(path) ? path : nil
      {% elsif flag?(:darwin) %}
        # macOS does not have /proc; use _NSGetExecutablePath via libc.
        buf = Bytes.new(4096)
        size = buf.size.to_u32
        ret = LibC._NSGetExecutablePath(buf.to_unsafe.as(UInt8*), pointerof(size))
        ret == 0 ? String.new(buf.to_unsafe) : nil
      {% else %}
        nil
      {% end %}
    end

    @@addr2line_available : Bool? = nil

    private def self.addr2line_available? : Bool
      result = @@addr2line_available
      if result.nil?
        result = Process.find_executable("addr2line") != nil
        @@addr2line_available = result
      end
      result
    end
  end
end
