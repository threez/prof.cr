require "../frame"

module Prof
  # :nodoc:
  module Output
    # :nodoc:
    module Folded
      def self.write(io : IO, samples : Array(Array(Frame))) : Nil
        counts = Hash(String, Int32).new(0)

        samples.each do |stack|
          next if stack.empty?
          # Reverse so outermost (main) comes first, matching flamegraph convention
          key = stack.reverse_each.map(&.name).join(";")
          counts[key] += 1
        end

        counts.each do |stack_str, count|
          io << stack_str << ' ' << count << '\n'
        end
      end
    end
  end
end
