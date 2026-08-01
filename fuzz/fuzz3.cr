require "../src/virtualtime"

# fuzz3:
#  part A: strict=false. Expected: first date d >= hint date with matches_date?,
#          result = d at hint's time-of-day.
#  part B: year pinned in past: no raise; result matches; succ raises.
#  part C: fixed-offset location on the VT, hint in UTC.

seed = (ARGV[0]? || "1").to_u64
r = Random.new(seed)
bugs = 0
testedA = testedB = testedC = 0

def gen_date_rules(r, vt)
  case r.rand(5)
  when 0
    vt.day = r.rand(2) == 0 ? r.rand(1..28) : -1
  when 1
    vt.month = r.rand(1..12)
    vt.day = [r.rand(1..15), r.rand(16..28)]
  when 2
    vt.day_of_week = r.rand(1..7)
  when 3
    vt.week = r.rand(2) == 0 ? r.rand(1..52) : -1
  else
    vt.day_of_year = r.rand(2) == 0 ? r.rand(1..365) : -r.rand(1..30)
  end
end

# Part A: strict = false
800.times do |iter|
  vt = VirtualTime.new
  gen_date_rules(r, vt)
  # also give it TOD rules that the hint will NOT satisfy, to prove they are ignored
  vt.hour = r.rand(0..23)
  vt.minute = r.rand(0..59) if r.rand(2) == 0

  hint = Time.utc(r.rand(2020..2026), r.rand(1..12), r.rand(1..28), r.rand(0..23), r.rand(0..59), r.rand(0..59))

  # brute
  exp = nil
  1000.times do |i|
    d = Time.utc(hint.year, hint.month, hint.day).shift(days: i)
    if vt.matches_date?(d)
      exp = Time.utc(d.year, d.month, d.day, hint.hour, hint.minute, hint.second)
      break
    end
  end
  next unless exp
  testedA += 1

  begin
    got = vt.to_time(hint, false)
    if got != exp
      bugs += 1
      puts "BUG strictfalse seed=#{seed} iter=#{iter} vt=#{vt.inspect}"
      puts "   hint=#{hint} expected=#{exp} (date-matches=#{vt.matches_date?(exp)}) got=#{got}"
    end
  rescue e : ArgumentError
    bugs += 1
    puts "BUG strictfalse-raise seed=#{seed} iter=#{iter} vt=#{vt.inspect} hint=#{hint} exp=#{exp} err=#{e.message.to_s[0, 120]}"
  end
  break if bugs >= 10
end
puts "partA tested=#{testedA} bugs=#{bugs}"

# Part B: year pinned in the past
400.times do |iter|
  vt = VirtualTime.new
  vt.year = r.rand(2015..2021)
  gen_date_rules(r, vt)
  vt.hour = r.rand(0..23) if r.rand(2) == 0

  hint = Time.utc(r.rand(2023..2026), r.rand(1..12), r.rand(1..28))
  testedB += 1

  begin
    got = vt.to_time(hint)
    unless vt.matches?(got)
      bugs += 1
      puts "BUG pastyear-nomatch seed=#{seed} iter=#{iter} vt=#{vt.inspect} hint=#{hint} got=#{got}"
    end
  rescue e : ArgumentError
    # A raise is fine only if the rule is truly unsatisfiable (e.g. week 53 in a
    # 52-week pinned year). Verify by brute over the pinned year.
    y = vt.year.as(Int32)
    sat = nil
    d = Time.utc(y, 1, 1)
    (Time.days_in_year(y)).times do |i|
      dd = d.shift(days: i)
      if vt.matches_date?(dd)
        sat = dd
        break
      end
    end
    if sat
      bugs += 1
      puts "BUG pastyear-raise seed=#{seed} iter=#{iter} vt=#{vt.inspect} hint=#{hint} satisfiable-at=#{sat} err=#{e.message.to_s[0, 140]}"
    end
  end

  # succ must raise or return > from
  begin
    s = vt.succ(hint)
    unless s > hint && vt.matches?(s)
      bugs += 1
      puts "BUG pastyear-succ seed=#{seed} iter=#{iter} vt=#{vt.inspect} from=#{hint} got=#{s}"
    end
  rescue ArgumentError
    # expected for bygone-year rules
  end
  break if bugs >= 10
end
puts "partB tested=#{testedB} bugs=#{bugs}"

# Part C: fixed-offset location
fixed = Time::Location.fixed(2 * 3600)
400.times do |iter|
  vt = VirtualTime.new
  vt.location = fixed
  gen_date_rules(r, vt)
  vt.hour = r.rand(0..23)
  vt.minute = r.rand(0..59)
  vt.second = 0
  vt.nanosecond = 0

  hint_utc = Time.utc(r.rand(2020..2026), r.rand(1..12), r.rand(1..28), r.rand(0..23), r.rand(0..59), 0)
  hint = hint_utc.in(fixed)

  # brute in fixed location
  exp = nil
  d0 = Time.local(hint.year, hint.month, hint.day, location: fixed)
  1000.times do |i|
    d = d0.shift(days: i)
    break if exp
    next unless vt.matches_date?(d)
    cand = Time.local(d.year, d.month, d.day, vt.hour.as(Int32), vt.minute.as(Int32), 0, location: fixed)
    if cand >= hint && vt.matches?(cand)
      exp = cand
    elsif cand < hint
      next
    end
  end
  next unless exp
  testedC += 1

  begin
    got = vt.to_time(hint_utc)
    if got != exp
      bugs += 1
      puts "BUG fixedloc seed=#{seed} iter=#{iter} vt=#{vt.inspect}"
      puts "   hint=#{hint_utc} (=#{hint}) expected=#{exp} got=#{got} (matches=#{vt.matches?(got)})"
    end
  rescue e : ArgumentError
    bugs += 1
    puts "BUG fixedloc-raise seed=#{seed} iter=#{iter} vt=#{vt.inspect} hint=#{hint_utc} exp=#{exp} err=#{e.message.to_s[0, 120]}"
  end
  break if bugs >= 10
end
puts "partC tested=#{testedC} bugs=#{bugs}"
