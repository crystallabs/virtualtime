require "../src/virtualtime"

# Fuzz succ chains and StepIterator:
# - succ must be > from, must match
# - succ must be the earliest match strictly after from (brute check)
# - step(by: n) must equal every n-th element of the succ chain (with default interval semantics)

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

def brute(vt, hint : Time, horizon_days = 800) : Time?
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
r = Random.new(seed)
bugs = 0
tested = 0

def gen_tod(r) : VirtualTime::Virtual
  case r.rand(5)
  when 0 then r.rand(0..23)
  when 1 then [r.rand(0..11), r.rand(12..23)]
  when 2 then r.rand(0..10)..r.rand(11..23)
  when 3 then 0.step(to: 23, by: r.rand(2..8))
  else        -r.rand(1..23)
  end
end

300.times do |iter|
  vt = VirtualTime.new
  vt.hour = gen_tod(r)
  vt.minute = case r.rand(4)
              when 0 then r.rand(0..59)
              when 1 then 0.step(to: 59, by: 15)
              when 2 then [0, 30]
              else        r.rand(0..29)..r.rand(30..59)
              end
  vt.second = 0
  vt.nanosecond = 0
  case r.rand(3)
  when 0
    vt.day = case r.rand(3)
             when 0 then r.rand(1..28)
             when 1 then -1
             else        [r.rand(1..15), r.rand(16..28)]
             end
  when 1
    vt.day_of_week = r.rand(1..7)
  else
    # date unconstrained
  end

  from = Time.utc(r.rand(2020..2026), r.rand(1..12), r.rand(1..28), r.rand(0..23), r.rand(0..59), r.rand(0..59))
  tested += 1

  # succ chain of 5
  prev = from
  chain = [] of Time
  ok = true
  5.times do
    begin
      nxt = vt.succ(prev)
      unless nxt > prev && vt.matches?(nxt)
        puts "BUG succ seed=#{seed} iter=#{iter} vt=#{vt.inspect} from=#{prev} got #{nxt} (matches=#{vt.matches?(nxt)})"
        bugs += 1; ok = false
        break
      end
      exp = brute(vt, prev + 1.nanosecond)
      if exp && exp != nxt
        puts "BUG succ-skip seed=#{seed} iter=#{iter} vt=#{vt.inspect}"
        puts "   from=#{prev} expected #{exp} (matches=#{vt.matches?(exp)}) got #{nxt}"
        bugs += 1; ok = false
        break
      end
      chain << nxt
      prev = nxt
    rescue e : ArgumentError
      puts "BUG succ-raise seed=#{seed} iter=#{iter} vt=#{vt.inspect} from=#{prev} err=#{e.message.to_s[0, 120]}"
      bugs += 1; ok = false
      break
    end
  end
  next unless ok

  # StepIterator by: 1 -- first 5 elements should equal chain (interval 1 minute
  # and matches at >= minute apart given second: 0 rule uniqueness per minute...
  # matches are exactly minute-aligned so interval-1.minute resumption cannot skip)
  it = vt.step(1.minute, 1, from)
  got = [] of Time
  5.times do
    v = it.next
    break if v.is_a? Iterator::Stop
    got << v
  end
  if got != chain
    puts "BUG step-by1 seed=#{seed} iter=#{iter} vt=#{vt.inspect} from=#{from}"
    puts "   chain=#{chain}"
    puts "   step =#{got}"
    bugs += 1
    next
  end

  # by: 2 should give every other element
  it2 = vt.step(1.minute, 2, from)
  got2 = [] of Time
  3.times do
    v = it2.next
    break if v.is_a? Iterator::Stop
    got2 << v
  end
  exp2 = [chain[0], chain[2], chain[4]]
  if got2 != exp2
    puts "BUG step-by2 seed=#{seed} iter=#{iter} vt=#{vt.inspect} from=#{from}"
    puts "   expected=#{exp2}"
    puts "   got     =#{got2}"
    bugs += 1
  end
  break if bugs >= 10
end

puts "done tested=#{tested} bugs=#{bugs}"
