require "../src/virtualtime"

# Fuzzer 2: richer value types (step iterators, negatives in arrays/ranges,
# procs), second-level granularity brute force using field-wise filtering.

UTC = Time::Location::UTC

def gen_field(r : Random, min : Int32, max : Int32) : VirtualTime::Virtual
  span = max - min
  case r.rand(8)
  when 0 then r.rand(min..max - 1)
  when 1
    a = r.rand(min..max - 1); b = r.rand(min..max - 1)
    a, b = b, a if a > b
    r.rand(2) == 0 ? (a..b) : (a...b + 1)
  when 2
    n = r.rand(1..4)
    Array(Int32).new(n) { r.rand(2) == 0 ? r.rand(min..max - 1) : -r.rand(1..span) }.uniq
  when 3 then -r.rand(1..span)
  when 4
    # step iterator ascending
    a = r.rand(min..max - 1); b = r.rand(min..max - 1)
    a, b = b, a if a > b
    st = r.rand(1..[span // 4, 1].max)
    a.step(to: b, by: st)
  when 5
    # step iterator with negative bounds
    a = -r.rand(1..span); b = r.rand(min..max - 1)
    lo, hi = {a, b}.min, {a, b}.max
    st = r.rand(1..[span // 4, 1].max)
    lo.step(to: hi, by: st)
  when 6
    # negative range
    a = -r.rand(2..span); b = -r.rand(1..span)
    a, b = b, a if a > b
    a..b
  else
    # proc
    k = r.rand(2..7)
    off = r.rand(0..k - 1)
    ->(v : Int32) { v % k == off }
  end
end

# Earliest time-of-day (h,m,s) on `day` at/after `from` matching vt's TOD rules.
def first_tod(vt, day : Time, from : Time) : Time?
  24.times do |h|
    next unless vt.matches?(vt.hour, h, 24)
    60.times do |m|
      next unless vt.matches?(vt.minute, m, 60)
      60.times do |s|
        next unless vt.matches?(vt.second, s, 60)
        cand = day + (h * 3600 + m * 60 + s).seconds
        next if cand < from
        return cand
      end
    end
  end
  nil
end

def brute(vt, hint : Time, horizon_days = 900) : Time?
  day0 = Time.utc(hint.year, hint.month, hint.day)
  horizon_days.times do |i|
    d = day0.shift(days: i)
    next unless vt.matches_date?(d)
    if t = first_tod(vt, d, hint)
      return t
    end
  end
  nil
end

seed = (ARGV[0]? || "1").to_u64
n_iters = (ARGV[1]? || "2000").to_i
r = Random.new(seed)
bugs = 0
tested = 0

n_iters.times do |iter|
  year = r.rand(2019..2027)
  month = r.rand(1..12)
  dmax = Time.days_in_month(year, month)
  day = r.rand(1..dmax)

  vt = VirtualTime.new

  # time-of-day rules: all constrained -> arbitrary hint TOD; else midnight hint
  all_tod = r.rand(2) == 0
  if all_tod
    vt.hour = gen_field(r, 0, 24)
    vt.minute = gen_field(r, 0, 60)
    vt.second = gen_field(r, 0, 60)
    hint = Time.utc(year, month, day, r.rand(0..23), r.rand(0..59), r.rand(0..59))
  else
    vt.hour = gen_field(r, 0, 24) if r.rand(2) == 0
    hint = Time.utc(year, month, day)
  end

  # date rules
  case r.rand(4)
  when 0
    vt.month = gen_field(r, 1, 13)
    vt.day = gen_field(r, 1, 29) # keep day sane-ish, negatives ok
  when 1
    vt.day_of_week = gen_field(r, 1, 8)
    vt.week = gen_field(r, 1, 53) if r.rand(3) == 0
  when 2
    vt.day_of_year = gen_field(r, 1, 366)
  else
    vt.month = gen_field(r, 1, 13)
    vt.day = gen_field(r, 1, 29)
    vt.day_of_week = gen_field(r, 1, 8) if r.rand(3) == 0
  end
  vt.year = year..(year + 1) if r.rand(4) == 0

  # skip rules that permit nothing (empty lists after uniq, etc.)
  expected = brute(vt, hint)
  next if expected.nil?

  tested += 1
  actual =
    begin
      vt.to_time(hint)
    rescue e : ArgumentError
      msg = e.message.to_s
      if msg.includes?("materializ") # known bug class 1: empty-vs-month-length
        next
      end
      bugs += 1
      puts "BUG(raise) seed=#{seed} iter=#{iter} vt=#{vt.inspect} hint=#{hint} expected=#{expected} error=#{msg[0, 160]}"
      next
    end

  if actual != expected
    ok_exp = vt.matches?(expected) && expected >= hint
    stat = vt.matches?(actual) ? "matches" : "NOMATCH"
    bugs += 1
    puts "BUG seed=#{seed} iter=#{iter} vt=#{vt.inspect}"
    puts "   hint=#{hint} expected=#{expected}(valid=#{ok_exp}) actual=#{actual}(#{stat})"
  end
  break if bugs >= 12
end

puts "done: tested=#{tested} bugs=#{bugs}"
