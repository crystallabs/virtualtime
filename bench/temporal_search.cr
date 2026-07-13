require "benchmark"
require "../src/virtualtime"

ITER = 50_000

puts "VirtualTime::Search performance benchmarks ×#{ITER}"
puts "Crystal #{Crystal::VERSION}"
puts

loc = Time::Location.load("Europe/Berlin")
base = Time.local(2023, 3, 26, 1, 30, 0, location: loc)
target = base + 1.hour

puts "Base time: #{base}"
puts "Target:    #{target}"
puts

Benchmark.bm do |x|
  x.report("Dense inverse search ×#{ITER}") do
    ITER.times do
      VirtualTime::Search.shifted_from_base?(
        target,
        1.minute,
        max_shift: 1000.minutes,
        max_shifts: 1000
      ) do |candidate|
        candidate == base ? 1.hour : nil
      end
    end
  end

  x.report("Negative step search ×#{ITER}") do
    ITER.times do
      VirtualTime::Search.shifted_from_base?(
        target,
        -1.minute,
        max_shift: 500.minutes,
        max_shifts: 500
      ) do |candidate|
        candidate == base ? 1.hour : nil
      end
    end
  end

  x.report("Blocked-window stress ×#{ITER}") do
    ITER.times do
      blocked =
        ->(t : Time) do
          (base - 3.hours) <= t && t <= (base + 3.hours)
        end

      VirtualTime::Search.shift_from_base(
        base,
        1.minute,
        max_shift: 1000.minutes,
        max_shifts: 1000,
        &blocked
      )
    end
  end

  x.report("Zero-hit search (early termination) ×#{ITER}") do
    ITER.times do
      VirtualTime::Search.shifted_from_base?(
        target,
        1.minute,
        max_shift: 10.minutes,
        max_shifts: 10
      ) { nil }
    end
  end
end

puts
puts "Done."
