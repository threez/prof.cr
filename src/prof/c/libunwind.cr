# Crystal's stdlib already binds _Unwind_Backtrace and _Unwind_GetIP in its own
# LibUnwind (src/exception/call_stack/libunwind.cr), including the @[Link("unwind")]
# annotation.  Redefining LibUnwind here with different types causes a "fun
# redefinition with different signature" error, so this file is intentionally empty.
# sampler.cr uses Crystal's stdlib LibUnwind directly on FreeBSD and other non-Linux non-Darwin platforms.
