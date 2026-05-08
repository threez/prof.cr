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
{% if flag?(:darwin) || flag?(:linux) %}
  lib LibExecinfo
    fun backtrace(buffer : Void**, size : LibC::Int) : LibC::Int
    fun backtrace_symbols(buffer : Void**, size : LibC::Int) : UInt8**
  end
{% end %}
