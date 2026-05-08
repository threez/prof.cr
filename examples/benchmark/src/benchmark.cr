require "prof"

# Three distinct workloads so the profile shows clearly separated hot frames.

@[NoInline]
def fib(n : Int64) : Int64
  return n if n <= 1
  fib(n - 1) &+ fib(n - 2)
end

@[NoInline]
def sieve(limit : Int32) : Int32
  composite = Array(Bool).new(limit + 1, false)
  i = 2
  while i * i <= limit
    unless composite[i]
      j = i * i
      while j <= limit
        composite[j] = true
        j += i
      end
    end
    i += 1
  end
  composite.count(false) - 2 # subtract indices 0 and 1
end

@[NoInline]
def sort_work(size : Int32) : Int64
  rng = Random.new(42)
  arr = Array(Int32).new(size) { rng.next_int }
  arr.sort!
  arr.sum(&.to_i64)
end

report = Prof.profile(interval: 500.microseconds, max_samples: 50_000) do
  10.times do
    fib(38_i64)
    sieve(500_000)
    sort_work(100_000)
  end
end

puts "Samples collected : #{report.total_samples}"
puts "Interval          : #{report.interval}"
puts ""
puts "Top 15 frames:"
puts "-" * 60
report.top(15).each_with_index do |(frame, count), i|
  pct = (count.to_f / report.total_samples * 100).round(1)
  puts "%3d. %5d samples (%5.1f%%)  %s" % {i + 1, count, pct, frame}
end

path = "profile.json"
report.to_speedscope(path)
puts ""
puts "Speedscope profile written to #{path}"
puts "Open https://www.speedscope.app and drag the file in."
