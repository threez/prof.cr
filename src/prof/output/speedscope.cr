require "json"
require "../frame"

module Prof
  # :nodoc:
  module Output
    # :nodoc:
    module Speedscope
      def self.write(
        io : IO,
        samples : Array(Array(Frame)),
        interval : Time::Span,
        name : String = "CPU Profile",
      ) : Nil
        # Build deduplicated frame list preserving insertion order.
        frame_index = {} of String => Int32
        frame_list = [] of Frame

        samples.each do |stack|
          stack.each do |frame|
            unless frame_index.has_key?(frame.name)
              frame_index[frame.name] = frame_list.size
              frame_list << frame
            end
          end
        end

        interval_ms = interval.total_milliseconds
        total_ms = samples.size * interval_ms

        JSON.build(io) do |json|
          json.object do
            json.field "$schema", "https://www.speedscope.app/file-format-schema.json"
            json.field "version", "0.0.1"

            json.field "shared" do
              json.object do
                json.field "frames" do
                  json.array do
                    frame_list.each do |frame|
                      json.object do
                        json.field "name", frame.name
                        json.field "file", frame.file if frame.file
                        json.field "line", frame.line if frame.line
                      end
                    end
                  end
                end
              end
            end

            json.field "profiles" do
              json.array do
                json.object do
                  json.field "type", "sampled"
                  json.field "name", name
                  json.field "unit", "milliseconds"
                  json.field "startValue", 0.0
                  json.field "endValue", total_ms

                  json.field "samples" do
                    json.array do
                      samples.each do |stack|
                        json.array do
                          # speedscope wants outermost→innermost; backtrace gives innermost first
                          stack.reverse_each { |frame| json.number frame_index[frame.name] }
                        end
                      end
                    end
                  end

                  json.field "weights" do
                    json.array { samples.size.times { json.number interval_ms } }
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
