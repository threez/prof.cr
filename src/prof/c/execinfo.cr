# Bindings for backtrace() and backtrace_symbols() from <execinfo.h>.
# backtrace_symbols(3) reads the static .symtab which has full Crystal method names
# (e.g. *Int64@Int#check_div_argument<Int32>:Nil).  dladdr(3) reads the dynamic
# .dynsym where Crystal uses ELF symbol versioning, so it returns only the base
# type name (*Int64) — the method signature is in the version string that dladdr
# does not expose.  Use backtrace_symbols wherever it is available.
#
# Darwin:      libSystem (always linked), no explicit @[Link] needed.
# Linux/glibc: also available with no extra link (glibc provides execinfo.h).
# Linux/musl:  not supported — compile-time error raised in sampler.cr.
# FreeBSD:     base-system libexecinfo provides an identical backtrace()/
#              backtrace_symbols() signature to glibc's, but (unlike Darwin/
#              glibc) needs an explicit link — it isn't pulled in by libc by
#              default. See sampler.cr's own header comment for why FreeBSD
#              uses this path at all instead of libunwind's _Unwind_Backtrace
#              (the fallback every other non-Linux non-Darwin platform still
#              uses): _Unwind_Backtrace's DWARF-CFI-based unwinding turned out
#              to be unsafe to run from inside a SIGPROF handler on FreeBSD
#              specifically, reliably crashing (SIGSEGV inside libgcc_s's own
#              _Unwind_Backtrace/_Unwind_SetIP) under any allocation-heavy
#              workload — almost certainly SIGPROF racing Boehm GC's own
#              stop-the-world thread-suspend signal, corrupting the
#              interrupted thread's saved register state out from under the
#              unwinder. backtrace(3)/libexecinfo does its own, much simpler
#              frame-pointer-chain walk instead of DWARF CFI lookups, which
#              doesn't appear to hit this failure mode (matches what
#              cvm/profiler.c's own C-level SIGPROF sampler already uses
#              successfully on this same platform, via cvm/Makefile's own
#              conditional -lexecinfo).
{% if flag?(:darwin) || flag?(:linux) %}
  lib LibExecinfo
    fun backtrace(buffer : Void**, size : LibC::Int) : LibC::Int
    fun backtrace_symbols(buffer : Void**, size : LibC::Int) : UInt8**
  end
{% elsif flag?(:freebsd) %}
  @[Link("execinfo")]
  lib LibExecinfo
    fun backtrace(buffer : Void**, size : LibC::Int) : LibC::Int
    fun backtrace_symbols(buffer : Void**, size : LibC::Int) : UInt8**
  end
{% end %}
