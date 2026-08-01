require "../src/virtualtime"

# Fuzzer: generates rules where "earliest match >= hint" is unambiguous
# (all date-fill ambiguity avoided), computes to_time, compares against
# brute-force scan.
#
# Modes:
#  A: hint at midnight, rule has at least one of week/dow/doy (date settled by rules)
#  B: hint at midnight, month+day both constrained
#  C: hint mid-day (second=0,ns=0), hour+minute constrained, date nil or constrained
#
# In all modes: second is nil or 0; millisecond/nanosecond nil.

UTC = Time::Location::UTC

struct Gen
  def initialize(@r : Random)
  end

  def int_field(min, max, allow_neg = false)
    case @r.rand(4)
    when 0 then @r.rand(min..max)
    when 1
      a = @r.rand(min..max); b = @r.rand(min..max)
      a, b = b, a if a > b
      a..b
    when 2
      n = @r.rand(1..3)
      Array(Int32).new(n) { @r.rand(min..max) }.uniq.sort
    else
      allow_neg ? -@r.rand(1..3) : @r.rand(min..max)
    end
  end
end

def brute(vt, hint : Time, horizon_days = 900) : Time?
  day0 = Time.utc(hint.year, hint.month, hint.day)
  horizon_days.times do |i|
    d = day0.shift(days: i)
    next unless vt.matches_date?(d)
    1440.times do |mi|
      cand = d + (mi * 60).seconds
      next if cand < hint
      return cand if vt.matches_time?(cand)
    end
  end
  nil
end

seed = (ARGV[0]? || "1").to_u64
r = Random.new(seed)
g = Gen.new(r)
bugs = 0
tested = 0

3000.times do |iter|
  mode = r.rand(3)
  year = r.rand(2019..2027)
  month = r.rand(1..12)
  dmax = Time.days_in_month(year, month)
  day = r.rand(1..dmax)

  vt = VirtualTime.new

  case mode
  when 0 # Mode A: week/dow/doy rules, midnight hint
    hint = Time.utc(year, month, day)
    if r.rand(2) == 0
      vt.week = case r.rand(4)
                when 0 then r.rand(1..52)
                when 1 then -1
                when 2 then r.rand(1..20)..r.rand(21..52)
                else        [r.rand(1..26), r.rand(27..52)]
                end
    end
    if r.rand(2) == 0
      vt.day_of_week = case r.rand(3)
                       when 0 then r.rand(1..7)
                       when 1 then [r.rand(1..3), r.rand(4..7)]
                       else        r.rand(1..3)..r.rand(4..7)
                       end
    end
    if vt.week.nil? && vt.day_of_week.nil?
      vt.day_of_year = case r.rand(3)
                       when 0 then r.rand(1..365)
                       when 1 then -r.rand(1..40)
                       else        [r.rand(1..180), r.rand(181..365)]
                       end
    end
    # optionally constrain year/month too
    vt.year = year..(year + 1) if r.rand(3) == 0
    vt.month = g.int_field(1, 12, true) if r.rand(4) == 0 && vt.day_of_year.nil?
    # time-of-day: constrained or nil
    if r.rand(2) == 0
      vt.hour = g.int_field(0, 23, true)
      vt.minute = g.int_field(0, 59, true) if r.rand(2) == 0
    end
    vt.second = 0 if r.rand(2) == 0
  when 1 # Mode B: month+day constrained, midnight hint
    hint = Time.utc(year, month, day)
    vt.month = g.int_field(1, 12, true)
    vt.day = case r.rand(5)
             when 0 then r.rand(1..28)
             when 1 then -1
             when 2 then -r.rand(1..5)
             when 3 then [r.rand(1..15), r.rand(16..31)]
             else        r.rand(1..10)..r.rand(11..31)
             end
    vt.year = year..(year + 1) if r.rand(3) == 0
    if r.rand(2) == 0
      vt.hour = g.int_field(0, 23, true)
      vt.minute = g.int_field(0, 59, true) if r.rand(2) == 0
    end
    vt.second = 0 if r.rand(2) == 0
  else # Mode C: mid-day hint, hour+minute constrained
    hint = Time.utc(year, month, day, r.rand(0..23), r.rand(0..59), 0)
    vt.hour = g.int_field(0, 23, true)
    vt.minute = g.int_field(0, 59, true)
    vt.second = 0 if r.rand(2) == 0
    if r.rand(2) == 0
      vt.month = g.int_field(1, 12, true)
      vt.day = case r.rand(4)
               when 0 then r.rand(1..28)
               when 1 then -1
               when 2 then [r.rand(1..15), r.rand(16..31)]
               else        r.rand(1..10)..r.rand(11..31)
               end
    end
  end

  expected = brute(vt, hint)
  next if expected.nil? # unsatisfiable within horizon; skip

  tested += 1
  actual =
    begin
      vt.to_time(hint)
    rescue e : ArgumentError
      bugs += 1
      puts "BUG(raise) seed=#{seed} iter=#{iter} vt=#{vt.inspect} hint=#{hint} expected=#{expected} error=#{e.message.to_s[0, 120]}"
      next
    end

  if actual != expected
    # Verify claim: expected must match and be >= hint
    ok_exp = vt.matches?(expected) && expected >= hint
    stat = vt.matches?(actual) ? "matches" : "NOMATCH"
    bugs += 1
    puts "BUG(mode#{mode}) seed=#{seed} iter=#{iter} vt=#{vt.inspect}"
    puts "   hint=#{hint} expected=#{expected}(valid=#{ok_exp}) actual=#{actual}(#{stat})"
  end
  break if bugs >= 15
end

puts "done: tested=#{tested} bugs=#{bugs}"
