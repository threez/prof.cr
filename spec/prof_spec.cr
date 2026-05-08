require "./spec_helper"

ADDR2LINE_AVAILABLE = Process.find_executable("addr2line") != nil

# Prevent the compiler from inlining these so they appear in stack traces.
@[NoInline]
def busy_inner : Int64
  sum = 0_i64
  5_000_000.times { |i| sum &+= i.to_i64 * i.to_i64 }
  sum
end

@[NoInline]
def busy_outer : Int64
  busy_inner &+ busy_inner &+ busy_inner
end

describe Prof::Resolver do
  describe "SKIP" do
    it "is 3 on Darwin and Linux/glibc, 2 on other platforms" do
      {% if flag?(:darwin) || flag?(:linux) %}
        Prof::Resolver::SKIP.should eq(3)
      {% else %}
        Prof::Resolver::SKIP.should eq(2)
      {% end %}
    end
  end

  {% if flag?(:darwin) || flag?(:linux) %}
    describe ".clean_name" do
      it "strips macOS leading columns and trailing offset" do
        Prof::Resolver.clean_name("1   mybinary   0xDEADBEEF   my_func + 42").should eq("my_func")
      end

      it "strips Linux parens and address suffix" do
        Prof::Resolver.clean_name("mybinary(my_func+0x10) [0xDEAD]").should eq("my_func")
      end

      it "handles Crystal generic type names with parens" do
        Prof::Resolver.clean_name("mybinary(*Pointer(Bool)+0x8) [0xDEAD]").should eq("*Pointer(Bool)")
      end

      it "handles decimal zero offset" do
        Prof::Resolver.clean_name("mybinary(my_func+0) [0xDEAD]").should eq("my_func")
      end

      it "falls back to raw when symbol strips to empty" do
        raw = "mybinary(+0x10) [0xDEAD]"
        Prof::Resolver.clean_name(raw).should eq(raw)
      end

      it "returns the string unchanged when format is unrecognized" do
        Prof::Resolver.clean_name("some_func").should eq("some_func")
      end
    end
  {% end %}
end

describe Prof do
  describe ".profile" do
    it "returns a Report with at least one sample" do
      report = Prof.profile(interval: 1.millisecond) { busy_outer }
      report.total_samples.should be > 0
    end

    it "each sample has at least one frame" do
      report = Prof.profile(interval: 1.millisecond) { busy_outer }
      report.samples.each do |stack|
        stack.size.should be > 0
      end
    end

    it "frames carry non-empty names" do
      report = Prof.profile(interval: 1.millisecond) { busy_outer }
      report.samples.each do |stack|
        stack.each(&.name.empty?.should(be_false))
      end
    end

    it "at least one frame name references the busy work functions" do
      report = Prof.profile(interval: 1.millisecond) { busy_outer }
      all_names = report.samples.flatten.map(&.name).join(" ")
      (all_names.includes?("busy_inner") || all_names.includes?("busy_outer")).should be_true
    end

    if ADDR2LINE_AVAILABLE
      it "resolves file:line for at least one frame when addr2line is available" do
        report = Prof.profile(interval: 1.millisecond) { busy_outer }
        frames_with_loc = report.samples.flatten.select(&.file)
        frames_with_loc.size.should be > 0
      end

      it "located frames carry a non-empty .cr file path and positive line number" do
        report = Prof.profile(interval: 1.millisecond) { busy_outer }
        located = report.samples.flatten.select(&.file)
        located.size.should be > 0
        located.each do |frame|
          frame.file.try(&.should(end_with(".cr")))
          (frame.line || 0).should be > 0
        end
      end

      it "at least one located frame references this spec file" do
        report = Prof.profile(interval: 1.millisecond) { busy_outer }
        spec_frames = report.samples.flatten.select { |frame|
          frame.file.try(&.includes?("prof_spec.cr"))
        }
        spec_frames.size.should be > 0
      end
    end

    it "frames carry non-zero addresses" do
      report = Prof.profile(interval: 1.millisecond) { busy_outer }
      report.samples.each do |stack|
        stack.each(&.address.should_not(eq(0_u64)))
      end
    end

    it "re-raises exceptions and leaves the profiler stopped" do
      expect_raises(Exception, "boom") do
        Prof.profile(interval: 1.millisecond) { raise "boom" }
      end
      # Profiler must be stopped so a subsequent run works without error.
      report = Prof.profile(interval: 1.millisecond) { busy_outer }
      report.total_samples.should be > 0
    end

    it "respects max_depth — stacks are no deeper than the limit" do
      report = Prof.profile(interval: 1.millisecond, max_depth: 4) { busy_outer }
      report.samples.each { |stack| stack.size.should be <= (4 - Prof::Resolver::SKIP) }
    end

    it "respects max_samples — total samples are capped at the limit" do
      report = Prof.profile(interval: 1.millisecond, max_samples: 3) { busy_outer }
      report.total_samples.should be <= 3
    end

    it "Report#interval reflects the configured interval via .profile" do
      report = Prof.profile(interval: 3.milliseconds) { busy_outer }
      report.interval.should eq(3.milliseconds)
    end
  end

  describe ".start / .stop" do
    it "can be used without the block form" do
      Prof.start(interval: 1.millisecond)
      busy_outer
      report = Prof.stop
      report.total_samples.should be > 0
    end

    it "raises if stop called when not running" do
      expect_raises(Exception, /not running/) { Prof.stop }
    end

    it "raises ArgumentError for max_samples <= 0" do
      expect_raises(ArgumentError, /max_samples/) { Prof.start(max_samples: 0) }
    end

    it "raises ArgumentError for max_depth <= 0" do
      expect_raises(ArgumentError, /max_depth/) { Prof.start(max_depth: 0) }
    end

    it "raises if start called while already running" do
      Prof.start(interval: 1.millisecond)
      expect_raises(Exception, /already running/) { Prof.start }
      Prof.stop
    end

    it "Report#interval reflects the configured interval" do
      Prof.start(interval: 2.milliseconds)
      busy_outer
      report = Prof.stop
      report.interval.should eq(2.milliseconds)
    end

    it "can run multiple profiling sessions in sequence" do
      3.times do
        report = Prof.profile(interval: 1.millisecond) { busy_outer }
        report.total_samples.should be > 0
      end
    end
  end

  describe "Frame" do
    it "#to_s returns the frame name when no location" do
      frame = Prof::Frame.new(0xdeadbeef_u64, "my_func + 42")
      frame.to_s.should eq("my_func + 42")
    end

    it "#to_s appends basename:line when location is present" do
      frame = Prof::Frame.new(0x1234_u64, "my_func", "/src/foo/bar.cr", 42)
      frame.to_s.should eq("my_func @ bar.cr:42")
    end

    it "exposes address and name getters" do
      frame = Prof::Frame.new(0x1234_u64, "foo")
      frame.address.should eq(0x1234_u64)
      frame.name.should eq("foo")
    end

    it "#location returns nil when no file" do
      Prof::Frame.new(0x1_u64, "f").location.should be_nil
    end

    it "#location returns file:line string when present" do
      frame = Prof::Frame.new(0x1_u64, "f", "/a/b/c.cr", 7)
      frame.location.should eq("/a/b/c.cr:7")
    end

    it "#location returns just the file path when line is absent" do
      frame = Prof::Frame.new(0x1_u64, "f", "/a/b/c.cr", nil)
      frame.location.should eq("/a/b/c.cr")
    end

    it "#to_s appends basename only when file present but line absent" do
      frame = Prof::Frame.new(0x1_u64, "f", "/a/b/c.cr", nil)
      frame.to_s.should eq("f @ c.cr")
    end
  end

  describe "Report" do
    it "empty report handles top, to_speedscope, to_folded, and to_s gracefully" do
      report = Prof::Report.new([] of Array(Prof::Frame), 1.millisecond)
      report.top(5).should be_empty
      io = IO::Memory.new
      report.to_speedscope(io)
      JSON.parse(io.to_s)["profiles"][0]["samples"].as_a.should be_empty
      io2 = IO::Memory.new
      report.to_folded(io2)
      io2.to_s.should be_empty
    end

    it "#total_samples matches samples array size" do
      report = Prof.profile(interval: 1.millisecond) { busy_outer }
      report.total_samples.should eq(report.samples.size)
    end

    it "#top returns the hottest frames" do
      report = Prof.profile(interval: 1.millisecond) { busy_outer }
      top = report.top(5)
      top.size.should be > 0
      top.each { |(_, count)| count.should be > 0 }
    end

    it "#top(n) limits result count to n" do
      report = Prof.profile(interval: 1.millisecond) { busy_outer }
      report.top(1).size.should eq(1)
      report.top(2).size.should be <= 2
    end

    it "#top(0) returns an empty array" do
      report = Prof.profile(interval: 1.millisecond) { busy_outer }
      report.top(0).should be_empty
    end

    it "#top results are sorted hottest first" do
      report = Prof.profile(interval: 1.millisecond) { busy_outer }
      counts = report.top(10).map { |(_, c)| c }
      counts.should eq(counts.sort.reverse!)
    end

    it "#to_speedscope writes valid JSON with required keys" do
      report = Prof.profile(interval: 1.millisecond) { busy_outer }
      io = IO::Memory.new
      report.to_speedscope(io)
      json = JSON.parse(io.to_s)
      json["version"].should eq("0.0.1")
      json["shared"]["frames"].as_a.size.should be > 0
      profile = json["profiles"][0]
      profile["type"].should eq("sampled")
      profile["samples"].as_a.size.should eq(report.total_samples)
      profile["weights"].as_a.size.should eq(report.total_samples)
    end

    if ADDR2LINE_AVAILABLE
      it "#to_speedscope includes file and line for located frames when addr2line is available" do
        report = Prof.profile(interval: 1.millisecond) { busy_outer }
        io = IO::Memory.new
        report.to_speedscope(io)
        frames = JSON.parse(io.to_s)["shared"]["frames"].as_a
        located = frames.select { |frame_json| frame_json["file"]? }
        located.size.should be > 0
        located.each do |frame_json|
          frame_json["file"].as_s.should_not be_empty
          frame_json["line"].as_i.should be > 0
        end
      end
    end

    it "#to_speedscope respects the name parameter" do
      report = Prof.profile(interval: 1.millisecond) { busy_outer }
      io = IO::Memory.new
      report.to_speedscope(io, name: "my profile")
      JSON.parse(io.to_s)["profiles"][0]["name"].should eq("my profile")
    end

    it "#to_speedscope endValue equals total_samples * interval_ms" do
      report = Prof.profile(interval: 2.milliseconds) { busy_outer }
      io = IO::Memory.new
      report.to_speedscope(io)
      json = JSON.parse(io.to_s)
      expected = report.total_samples * 2.0
      json["profiles"][0]["endValue"].as_f.should eq(expected)
    end

    it "#to_speedscope each weight equals the interval in ms" do
      report = Prof.profile(interval: 2.milliseconds) { busy_outer }
      io = IO::Memory.new
      report.to_speedscope(io)
      json = JSON.parse(io.to_s)
      json["profiles"][0]["weights"].as_a.each do |weight|
        weight.as_f.should eq(2.0)
      end
    end

    it "#to_speedscope writes to a file path" do
      report = Prof.profile(interval: 1.millisecond) { busy_outer }
      path = File.tempfile("prof_spec", ".json").path
      begin
        report.to_speedscope(path)
        JSON.parse(File.read(path))["version"].should eq("0.0.1")
      ensure
        File.delete(path) rescue nil
      end
    end

    it "#to_folded writes non-empty lines with counts" do
      report = Prof.profile(interval: 1.millisecond) { busy_outer }
      io = IO::Memory.new
      report.to_folded(io)
      lines = io.to_s.lines.reject(&.blank?)
      lines.size.should be > 0
      lines.each do |line|
        # Format is "frame;chain COUNT" — split at the last space
        idx = line.rindex(' ')
        idx.should_not be_nil
        if idx
          line[0...idx].should_not be_empty
          line[idx + 1..].to_i.should be > 0
        end
      end
    end

    it "#to_folded counts sum to total_samples" do
      report = Prof.profile(interval: 1.millisecond) { busy_outer }
      io = IO::Memory.new
      report.to_folded(io)
      total = io.to_s.lines.reject(&.blank?).sum do |line|
        line.split(' ').last.to_i
      end
      total.should eq(report.total_samples)
    end

    it "#to_folded writes to a file path" do
      report = Prof.profile(interval: 1.millisecond) { busy_outer }
      path = File.tempfile("prof_spec", ".folded").path
      begin
        report.to_folded(path)
        File.read(path).should_not be_empty
      ensure
        File.delete(path) rescue nil
      end
    end

    it "#to_s prints a summary with header and percentage column" do
      report = Prof.profile(interval: 1.millisecond) { busy_outer }
      summary = report.to_s
      summary.should contain("Prof::Report")
      summary.should contain("samples")
      summary.should match(/%/)
    end
  end
end
