{% if flag?(:musl) %}
  {% raise "Prof does not support musl libc. musl ≤1.2.5 provides no backtrace(3), " \
           "and Alpine 3.22+ ships neither libunwind nor libexecinfo, so there is no " \
           "reliable way to capture call stacks from a SIGPROF signal handler. " \
           "Use a glibc-based Linux distribution (Debian, Ubuntu, Fedora, etc.) instead." %}
{% end %}

require "c/signal"
require "./c/itimer"
{% if flag?(:darwin) || flag?(:linux) %}
  require "./c/execinfo"
{% else %}
  require "./c/libunwind"
{% end %}

module Prof
  # :nodoc:
  class Sampler
    @@frames_buf : UInt64* = Pointer(UInt64).null # flat [sample * max_depth]
    @@depths_buf : Int32* = Pointer(Int32).null   # actual depth per sample
    @@count : Int32 = 0
    @@max_samples : Int32 = 0
    @@max_depth : Int32 = 0
    @@old_action = LibC::Sigaction.new
    # Callback state for _Unwind_Backtrace (FreeBSD and other non-Linux non-Darwin platforms).
    # Class vars make the inner lambda non-capturing (async-signal-safe).
    @@cb_slot : UInt64* = Pointer(UInt64).null
    @@cb_n : Int32 = 0

    def self.start(interval_us : Int64, max_samples : Int32, max_depth : Int32) : Nil
      raise ArgumentError.new("max_samples must be > 0") if max_samples <= 0
      raise ArgumentError.new("max_depth must be > 0") if max_depth <= 0
      @@max_samples = max_samples
      @@max_depth = max_depth
      @@count = 0

      frames_ptr = LibC.malloc(max_samples.to_i64 * max_depth.to_i64 * sizeof(UInt64))
      raise "Prof: out of memory allocating frame buffer" if frames_ptr.null?
      @@frames_buf = frames_ptr.as(UInt64*)

      depths_ptr = LibC.malloc(max_samples.to_i64 * sizeof(Int32))
      if depths_ptr.null?
        LibC.free(@@frames_buf.as(Void*))
        @@frames_buf = Pointer(UInt64).null
        raise "Prof: out of memory allocating depth buffer"
      else
        @@depths_buf = depths_ptr.as(Int32*)
      end

      act = LibC::Sigaction.new
      # sa_mask: LibC::Sigaction.new already zero-initialises all fields, so
      # sa_mask is zeroed regardless of whether SigsetT is UInt32 (Darwin) or
      # StaticArray(UInt64, 16) (Linux). The explicit 0_u32 assignment from the
      # original code only compiled on Darwin; relying on .new is portable.
      act.sa_flags = LibC::SA_RESTART | LibC::SA_SIGINFO
      # Non-capturing lambda: @@vars are static globals, no closure needed.
      act.sa_sigaction = ->(sig : Int32, _info : LibC::SiginfoT*, _ctx : Void*) {
        idx = @@count
        return if idx >= @@max_samples
        slot = @@frames_buf + idx.to_i64 * @@max_depth

        # n is pre-declared so the type system sees it as Int32 after both branches.
        n = 0
        {% if flag?(:darwin) || flag?(:linux) %}
          # backtrace(3): libSystem on Darwin, glibc on Linux.
          # Not formally async-signal-safe but avoids malloc in practice on both.
          n = LibExecinfo.backtrace(slot.as(Pointer(Pointer(Void))), @@max_depth)
        {% else %}
          # FreeBSD, Solaris, and other non-Linux non-Darwin platforms.
          # Crystal's stdlib LibUnwind wraps _Unwind_Backtrace / _Unwind_GetIP.
          # Class vars pass state so the callback is non-capturing (async-signal-safe).
          # Frames: [0] signal handler, [1] OS trampoline, [2+] user code (SKIP = 2).
          @@cb_slot = slot
          @@cb_n = 0
          LibUnwind.backtrace(->(ctx : LibUnwind::Context, _arg : Void*) : LibUnwind::ReasonCode {
            return LibUnwind::ReasonCode::NORMAL_STOP if @@cb_n >= @@max_depth
            @@cb_slot[@@cb_n] = LibUnwind.get_ip(ctx).to_u64
            @@cb_n += 1
            LibUnwind::ReasonCode::NO_REASON
          }, nil)
          n = @@cb_n
        {% end %}

        @@depths_buf[idx] = n
        @@count = idx + 1
      }
      LibC.sigaction(LibC::SIGPROF, pointerof(act), pointerof(@@old_action))

      tv = LibC::Timeval.new
      tv.tv_sec = 0
      tv.tv_usec = interval_us
      itv = LibC::Itimerval.new
      itv.it_interval = tv
      itv.it_value = tv
      LibC.setitimer(LibC::ITIMER_PROF, pointerof(itv), nil)
    end

    # Stops the timer and restores the previous signal handler.
    # Returns the raw buffers for the caller to process and free.
    def self.stop : {UInt64*, Int32*, Int32, Int32}
      zero = LibC::Itimerval.new
      LibC.setitimer(LibC::ITIMER_PROF, pointerof(zero), nil)
      LibC.sigaction(LibC::SIGPROF, pointerof(@@old_action), nil)

      result = {@@frames_buf, @@depths_buf, @@count, @@max_depth}
      @@frames_buf = Pointer(UInt64).null
      @@depths_buf = Pointer(Int32).null
      @@count = 0
      result
    end
  end
end
