# sigsetjmp(3)/siglongjmp(3) bindings, FreeBSD/x86_64 only -- used by
# sampler.cr to recover from a SIGSEGV/SIGBUS that occurs INSIDE a single
# backtrace() attempt (see sampler.cr's own comment for the full story:
# FreeBSD's libexecinfo backtrace() is itself implemented via libgcc's
# _Unwind_Backtrace, which can fault when a SIGPROF sample lands during
# Boehm GC activity).
#
# sigjmp_buf's exact layout is architecture-specific (verified here only
# for FreeBSD/amd64, against /usr/include/x86/setjmp.h's own definition:
# `typedef struct _sigjmp_buf { long _sjb[_JBLEN]; } sigjmp_buf[1];` with
# `_JBLEN` 12) -- deliberately NOT extended to aarch64 FreeBSD without
# verifying ITS OWN _JBLEN first (getting this wrong would silently
# corrupt the stack instead of raising, since sigsetjmp/siglongjmp are
# raw memory operations with no type checking of their own); see
# sampler.cr's own guard for how a not-yet-verified arch instead falls
# back to plain, unprotected backtrace() -- exactly the pre-existing
# behavior everywhere before this fix, not a new regression.
#
# `sigjmp_buf` itself is a C array type (`sigjmp_buf[1]`), which decays to
# a pointer at any call site -- so the two functions below take a pointer
# to the underlying struct directly, matching that decay.
{% if flag?(:freebsd) && flag?(:x86_64) %}
  lib LibC
    alias SigjmpBuf = StaticArray(LibC::Long, 12)
    fun sigsetjmp(env : SigjmpBuf*, savesigs : Int32) : Int32
    fun siglongjmp(env : SigjmpBuf*, val : Int32) : NoReturn
  end
{% end %}
