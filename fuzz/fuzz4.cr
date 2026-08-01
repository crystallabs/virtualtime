require "../src/virtualtime"

# Part A: invariants in a DST zone (Europe/Berlin): to_time result matches and
# >= hint; succ chain strictly increasing and matching.
# Part B: millisecond-rule brute-force at ms granularity (UTC).

seed = (ARGV[0]? || "1").to_u64
r = Random.new(seed)
bugs = 0

berlin = Time::Location.load("Europe/Berlin")

600.times do |iter|
  vt = VirtualTime.new
  vt.hour = case r.rand(4)
            when 0 then r.rand(0..23)
            when 1 then [r.rand(0..4), r.rand(5..23)]
            when 2 then r.rand(0..4)..r.rand(5..23)
            else        nil
            end
  vt.minute = [0, 30].sample(r) if r.rand(2) == 0
  vt.second = 0
  vt.nanosecond = 0
  case r.rand(4)
  when 0 then vt.day_of_week = r.rand(1..7)
  when 1 then vt.day = r.rand(2) == 0 ? -1 : r.rand(1..28)
  when 2 then vt.week = r.rand(1..52)
  end

  # bias hints towards DST transitions (late March, late Oct) sometimes
  hint =
    case r.rand(3)
    when 0 then Time.local(r.rand(2020..2026), 3, r.rand(24..31), r.rand(0..23), r.rand(0..59), 0, location: berlin)
    when 1 then Time.local(r.rand(2020..2026), 10, r.rand(22..29), r.rand(0..23), r.rand(0..59), 0, location: berlin)
    else        Time.local(r.rand(2020..2026), r.rand(1..12), r.rand(1..28), r.rand(0..23), r.rand(0..59), 0, location: berlin)
    end

  begin
    t = vt.to_time(hint)
    unless vt.matches?(t) && t >= hint
      bugs += 1
      puts "BUG berlin seed=#{seed} iter=#{iter} vt=#{vt.inspect} hint=#{hint} got=#{t} matches=#{vt.matches?(t)} >=hint=#{t >= hint}"
    end
  rescue e : ArgumentError
    bugs += 1
    puts "BUG berlin-raise seed=#{seed} iter=#{iter} vt=#{vt.inspect} hint=#{hint} err=#{e.message.to_s[0, 140]}"
  end

  # succ chain
  prev = hint
  4.times do
    begin
      nxt = vt.succ(prev)
      unless nxt > prev && vt.matches?(nxt)
        bugs += 1
        puts "BUG berlin-succ seed=#{seed} iter=#{iter} vt=#{vt.inspect} from=#{prev} got=#{nxt} matches=#{vt.matches?(nxt)}"
        break
      end
      prev = nxt
    rescue e : ArgumentError
      bugs += 1
      puts "BUG berlin-succ-raise seed=#{seed} iter=#{iter} vt=#{vt.inspect} from=#{prev} err=#{e.message.to_s[0, 140]}"
      break
    end
  end
  break if bugs >= 10
end
puts "partA done bugs=#{bugs}"

# Part B: millisecond rules, UTC, brute at ms granularity
def gen_ms(r) : VirtualTime::Virtual
  case r.rand(5)
  when 0 then r.rand(0..999)
  when 1 then -r.rand(1..999)
  when 2 then Array(Int32).new(r.rand(1..4)) { r.rand(0..999) }.uniq
  when 3
    a = r.rand(0..998); b = r.rand(0..999)
    a, b = b, a if a > b
    a..b
  else
    a = r.rand(0..499)
    a.step(to: r.rand(500..999), by: r.rand(1..300))
  end
end

1000.times do |iter|
  vt = VirtualTime.new
  vt.millisecond = gen_ms(r)

  hint = Time.utc(2024, 5, 5, 12, 0, r.rand(0..50), nanosecond: r.rand(0..999) * 1_000_000 + r.rand(0..999_999))

  # brute expected
  hint_ms = hint.millisecond
  exp =
    if vt.matches?(vt.millisecond, hint_ms, 1000)
      hint
    elsif nxt = (hint_ms + 1..999).find { |v| vt.matches?(vt.millisecond, v, 1000) }
      Time.utc(2024, 5, 5, 12, 0, hint.second, nanosecond: nxt * 1_000_000)
    elsif fst = (0..999).find { |v| vt.matches?(vt.millisecond, v, 1000) }
      Time.utc(2024, 5, 5, 12, 0, hint.second + 1, nanosecond: fst * 1_000_000)
    else
      nil
    end
  next unless exp

  begin
    got = vt.to_time(hint)
    if got != exp
      bugs += 1
      puts "BUG ms seed=#{seed} iter=#{iter} ms=#{vt.millisecond.inspect} hint=#{hint} (ns=#{hint.nanosecond}) expected=#{exp} (ns=#{exp.nanosecond}) got=#{got} (ns=#{got.nanosecond}) matches=#{vt.matches?(got)}"
    end
  rescue e : ArgumentError
    bugs += 1
    puts "BUG ms-raise seed=#{seed} iter=#{iter} ms=#{vt.millisecond.inspect} hint=#{hint} err=#{e.message.to_s[0, 140]}"
  end
  break if bugs >= 10
end
puts "partB done bugs=#{bugs}"
