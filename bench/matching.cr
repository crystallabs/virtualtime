require "benchmark"
require "../src/virtualtime"

# Exercises the `VirtualTime#matches?` hot path, which scheduling loops
# (`#succ`, `#step`, `VirtualDate`'s shift search) call once per field per
# candidate time.

ITER = 200_000

puts "VirtualTime#matches? performance benchmarks ×#{ITER}"
puts "Crystal #{Crystal::VERSION}"
puts

time = Time.local 2023, 5, 10, 10, 30, 0
puts "Time: #{time}"
puts

int_vt = VirtualTime.new month: 5, day: 10, hour: 10
list_vt = VirtualTime.new month: [4, 5, 6], day: [1, 10, 20], hour: [9, 10, 11]
unsorted_vt = VirtualTime.new month: [6, 5, 4], day: [20, 10, 1], hour: [11, 10, 9]
negative_vt = VirtualTime.new month: -8, day: [1, -22], hour: -14
range_vt = VirtualTime.new month: 4..6, day: 1..20, hour: 9..11
step_vt = VirtualTime.new month: (4..6).step(1), day: (2..20).step(2), hour: (9..11).step(1)

# Two ranges wide enough that intersecting them by iteration is hopeless
wide_a = 0..999_999_999
wide_b = 500_000_000..600_000_000
wide_list = [1_500_000_000, 500_000_000]

Benchmark.bm do |x|
  x.report("Int fields") do
    ITER.times { int_vt.matches? time }
  end

  x.report("Sorted list fields") do
    ITER.times { list_vt.matches? time }
  end

  x.report("Unsorted list fields") do
    ITER.times { unsorted_vt.matches? time }
  end

  x.report("Negative (wrapping) fields") do
    ITER.times { negative_vt.matches? time }
  end

  x.report("Range fields") do
    ITER.times { range_vt.matches? time }
  end

  x.report("Stepped range fields") do
    ITER.times { step_vt.matches? time }
  end

  x.report("VT to VT (range vs range)") do
    ITER.times { range_vt.matches? step_vt }
  end

  x.report("Wide range vs wide range") do
    ITER.times { int_vt.matches? wide_a, wide_b, 1_000_000_000 }
  end

  x.report("Wide range vs list") do
    ITER.times { int_vt.matches? wide_a, wide_list, nil }
  end
end

puts
puts "Done."
