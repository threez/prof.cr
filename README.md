# prof.cr

A sampling CPU profiler for Crystal programs. Installs a `SIGPROF` handler
via `sigaction(2)`, fires it on a CPU-time interval set with `setitimer(2)`,
and captures the call stack into a pre-allocated buffer on every tick. After
stopping, addresses are resolved to symbol names and the result is a
`Prof::Report` you can inspect or export.

## Platform support

| Platform | Stack unwinding | Symbol resolution |
|---|---|---|
| macOS | `backtrace(3)` (libSystem) | `backtrace_symbols(3)` — full Crystal method names |
| Linux (glibc) | `backtrace(3)` (glibc) | `backtrace_symbols(3)` — full Crystal method names |
| Linux (musl) | **not supported** | — |
| FreeBSD | libunwind | `dladdr(3)` — type name only |
| Solaris | libunwind | `dladdr(3)` — type name only |
| QNX | libunwind | `dladdr(3)` — type name only |
| HP-UX | libunwind | `dladdr(3)` — type name only |

`ITIMER_PROF` fires on CPU time (user + kernel), so sleeping or waiting on I/O
does not accumulate samples.

### Dependencies

### No extra dependencies

macOS (libSystem) and Linux/glibc (glibc) provide `backtrace(3)` out of the
box. FreeBSD and other platforms use Crystal's bundled LLVM libunwind. No
extra packages are needed on any supported platform.

musl libc is **not supported**: musl ≤1.2.5 provides no `backtrace(3)`, and
Alpine 3.22 ships neither libunwind nor libexecinfo, making reliable signal-
handler stack collection impossible without additional system packages that are
no longer available. The library raises a compile-time error on musl.

## Installation

Add the dependency to your `shard.yml`:

```yaml
dependencies:
  prof:
    github: threez/prof.cr
```

Then run `shards install`.

## Usage

### Block form (recommended)

```crystal
require "prof"

report = Prof.profile(interval: 1.millisecond) do
  my_expensive_computation
end

puts report                          # top-10 hottest frames to stdout
report.to_speedscope("profile.json") # open at https://www.speedscope.app
report.to_folded("profile.folded")   # pipe to flamegraph.pl or import into speedscope
```

### Manual start / stop

```crystal
Prof.start(interval: 1.millisecond)

do_phase_one
do_phase_two

report = Prof.stop
puts report
```

### Options

```crystal
Prof.profile(
  interval:    1.millisecond,   # sampling interval (CPU time, min ~100µs)
  max_samples: 100_000,         # hard cap on number of samples collected
  max_depth:   64               # max stack frames captured per sample
) { ... }
```

### Reading the report

```crystal
report.total_samples          # number of samples captured
report.samples                # Array(Array(Prof::Frame))
report.top(10)                # Array({Frame, Int32}) sorted by sample count

report.samples.each do |stack|
  stack.each { |frame| puts "#{frame.name}  0x#{frame.address.to_s(16)}" }
end
```

### Exporting

| Method | Format | Viewer |
|---|---|---|
| `report.to_speedscope("out.json")` | speedscope sampled profile | [speedscope.app](https://www.speedscope.app) |
| `report.to_folded("out.folded")` | folded stacks | `flamegraph.pl` or speedscope import |

Both methods also accept an `IO` instead of a path.

## How it works

1. `Prof.start` allocates two `LibC.malloc` buffers (frame addresses + depths),
   installs a raw `sigaction` handler with `SA_RESTART | SA_SIGINFO`, and arms
   `setitimer(ITIMER_PROF, ...)`.
2. On each `SIGPROF`, the handler captures the current call stack into the
   pre-allocated buffer — no heap allocation, no Crystal runtime calls:
   - **macOS / Linux+glibc**: calls `backtrace(3)` from libSystem / glibc.
   - **FreeBSD / others**: calls `_Unwind_Backtrace` via Crystal's stdlib
     `LibUnwind` bindings.
3. `Prof.stop` disarms the timer, restores the previous signal handler, then
   resolves the captured addresses to symbol strings:
   - **macOS / Linux+glibc**: `backtrace_symbols(3)` in a single batch call;
     first 3 frames (backtrace call, signal handler, OS trampoline) are discarded.
   - **FreeBSD / others**: `dladdr(3)` per address, returning `sym+0xoffset`; first
     2 frames (signal handler, OS trampoline) are discarded.
4. Symbols are parsed into `Prof::Frame` structs and wrapped in a `Prof::Report`.

The signal handler is a non-capturing Crystal lambda assigned to `sa_sigaction`.
Because it only reads and writes class-level static variables (no heap
allocation, no closure), Crystal converts it to a plain C function pointer —
the same technique Crystal's own `Signal.trap` infrastructure uses internally.

## Limitations

### Thread safety

`ITIMER_PROF` is process-wide; only one profiler session can run at a time. The
profiler is **not safe** for use with `-Dpreview_mt` (multi-threaded Crystal):
the sample counter is a plain `Int32` incremented without an atomic operation,
so concurrent signal delivery can corrupt the count.

### Source location resolution (`--release`)

Source file and line numbers require both DWARF debug info and `addr2line` on
PATH. `crystal run` and `crystal build` (without `--release`) include debug info
by default. `crystal build --release` strips it, so `frame.file` and
`frame.line` will be `nil` — the profiler still collects samples and resolves
function names, but without source locations.

`addr2line` is usually available via the `binutils` package on Linux. On macOS
it is not installed by default; install it with `brew install binutils` or
ensure the LLVM toolchain's `addr2line` is on PATH.

## Development

```sh
crystal spec                        # run the test suite
crystal build src/prof.cr           # type-check the library (no output = success)
crystal spec spec/prof_spec.cr:42   # run a single test by line number
```

The spec uses `@[NoInline]` functions and a multi-million-iteration workload to
ensure the timer fires several times per test run across the range of machines.

## Contributing

1. Fork it (<https://github.com/threez/prof.cr/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Open a Pull Request

## Contributors

- [Vincent Landgraf](https://github.com/threez) - creator and maintainer
