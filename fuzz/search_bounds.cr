require "../src/virtualtime"

base = Time.utc(2025, 1, 1)
fails = 0

# --- shift_from_base ---

# 1. max_shifts inclusive: with max_shifts = 3, candidates base+1..base+3 must be evaluated.
evaluated = [] of Int32
r = VirtualTime::Search.shift_from_base(base, 1.hour, max_shifts: 3) do |t|
  evaluated << (t - base).total_hours.to_i
  true # always blocked
end
unless r.is_a?(VirtualTime::Result::Blocked) && evaluated == [1, 2, 3]
  fails += 1
  puts "FAIL max_shifts inclusive: evaluated=#{evaluated} result=#{r}"
end

# 2. candidate exactly at shift #3 accepted
r = VirtualTime::Search.shift_from_base(base, 1.hour, max_shifts: 3) { |t| (t - base) < 3.hours }
unless r.is_a?(VirtualTime::Result::Found) && r.delta == 3.hours
  fails += 1
  puts "FAIL max_shifts boundary accept: #{r}"
end

# 3. max_shift inclusive: delta exactly == max_shift allowed
r = VirtualTime::Search.shift_from_base(base, 1.hour, max_shift: 3.hours) { |t| (t - base) < 3.hours }
unless r.is_a?(VirtualTime::Result::Found) && r.delta == 3.hours
  fails += 1
  puts "FAIL max_shift inclusive accept: #{r}"
end

# 4. delta just over max_shift -> OutOfBounds
r = VirtualTime::Search.shift_from_base(base, 1.hour, max_shift: 3.hours) { |t| (t - base) < 4.hours }
unless r.is_a?(VirtualTime::Result::OutOfBounds)
  fails += 1
  puts "FAIL max_shift exceed: #{r}"
end

# 5. zero step
r = VirtualTime::Search.shift_from_base(base, 0.seconds) { true }
unless r.is_a?(VirtualTime::Result::InvalidStep)
  fails += 1
  puts "FAIL zero step: #{r}"
end

# 6. max_shifts <= 0
r = VirtualTime::Search.shift_from_base(base, 1.hour, max_shifts: 0) { false }
unless r.is_a?(VirtualTime::Result::Blocked)
  fails += 1
  puts "FAIL max_shifts=0: #{r}"
end

# 7. negative step with max_shift (abs)
r = VirtualTime::Search.shift_from_base(base, -1.hour, max_shift: 2.hours) { |t| (base - t) < 2.hours }
unless r.is_a?(VirtualTime::Result::Found) && r.delta == -2.hours
  fails += 1
  puts "FAIL negative step: #{r}"
end

# 8. domain
struct Window < VirtualTime::Domain
  def initialize(@from : Time, @to : Time); end

  def contains?(time : Time) : Bool
    @from <= time <= @to
  end
end

r = VirtualTime::Search.shift_from_base(base, 1.hour, domain: Window.new(base, base + 2.hours)) { |t| (t - base) < 3.hours }
unless r.is_a?(VirtualTime::Result::OutOfBounds)
  fails += 1
  puts "FAIL domain bound: #{r}"
end

# --- shifted_from_base? ---

# 9. exact reachability: target = base + 3h, step 1h; producer emits delta target-base when asked at real base.
target = base + 3.hours
called = [] of Int32
ok = VirtualTime::Search.shifted_from_base?(target, 1.hour, max_shifts: 3) do |b|
  called << (target - b).total_hours.to_i
  b == base ? (target - b) : nil
end
unless ok && called == [1, 2, 3]
  fails += 1
  puts "FAIL shifted_from_base? inclusive shifts: ok=#{ok} called=#{called}"
end

# 10. base one step beyond max_shifts -> false
ok = VirtualTime::Search.shifted_from_base?(target, 1.hour, max_shifts: 2) do |b|
  b == base ? (target - b) : nil
end
if ok
  fails += 1
  puts "FAIL shifted_from_base? should be false with max_shifts=2"
end

# 11. max_shift inclusive: distance exactly max_shift accepted
ok = VirtualTime::Search.shifted_from_base?(target, 1.hour, max_shift: 3.hours, max_shifts: 10) do |b|
  b == base ? (target - b) : nil
end
unless ok
  fails += 1
  puts "FAIL shifted_from_base? max_shift inclusive"
end

# 12. max_shift exclusive beyond: distance 3h but max_shift 2h -> false, and termination not too early:
#     base at distance exactly max_shift must still be probed.
probed = [] of Int32
ok = VirtualTime::Search.shifted_from_base?(target, 1.hour, max_shift: 2.hours, max_shifts: 10) do |b|
  probed << (target - b).total_hours.to_i
  nil
end
if ok || probed != [1, 2]
  fails += 1
  puts "FAIL termination: ok=#{ok} probed=#{probed} (expected [1, 2])"
end

# 13. zero step / non-positive max_shifts -> false
fails += 1 if VirtualTime::Search.shifted_from_base?(target, 0.seconds, max_shifts: 5) { |b| nil }
fails += 1 if VirtualTime::Search.shifted_from_base?(target, 1.hour, max_shifts: 0) { |b| nil }

# 14. implicit max via step.abs * max_shifts: base at 3 steps, max_shifts 3, no max_shift -> true
ok = VirtualTime::Search.shifted_from_base?(target, 1.hour, max_shifts: 3) { |b| b == base ? (target - b) : nil }
unless ok
  fails += 1
  puts "FAIL implicit effective_max_shift"
end

# 15. produced delta that does NOT reach target must be rejected
ok = VirtualTime::Search.shifted_from_base?(target, 1.hour, max_shifts: 5) { |b| 1.hour }
# base target-1h + 1h == target -> this one is genuinely true! producer says delta 1h from target-1h.
unless ok
  fails += 1
  puts "FAIL: first base with delta 1h reaches target, should be true"
end
ok = VirtualTime::Search.shifted_from_base?(target, 1.hour, max_shifts: 5) { |b| 30.minutes }
if ok
  fails += 1
  puts "FAIL: produced delta never reaches target, should be false"
end

puts "T6 done, #{fails} failures"
