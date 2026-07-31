require "spec"
require "../src/virtualtime"

# Example custom search domain that accepts times up to (and including) a cutoff.
struct CutoffDomain < VirtualTime::Domain
  def initialize(@cutoff : Time)
  end

  def contains?(time : Time) : Bool
    time <= @cutoff
  end
end

# Simple shrinker for fuzzer-found problems:
# try to reduce delta and step, then normalize time-of-day
def shrink_case(
  base : Time,
  step : Time::Span,
  delta : Time::Span,
  max_shift : Time::Span,
  max_shifts : Int32,
  &fails : (Time, Time::Span, Time::Span) -> Bool
)
  shrunk = {base, step, delta}

  # delta
  while delta.abs > 1.minute
    smaller = (delta / 2)
    break unless fails.call(base, step, smaller)
    delta = smaller
    shrunk = {base, step, delta}
  end

  # step
  while step.abs > 1.minute
    smaller = (step / 2)
    break if smaller == 0.seconds
    break unless fails.call(base, smaller, delta)
    step = smaller
    shrunk = {base, step, delta}
  end

  # normalize time-of-day
  normalized = Time.local(base.year, base.month, base.day, 0, 0, 0, location: base.location)

  if fails.call(normalized, step, delta)
    shrunk = {normalized, step, delta}
  end

  shrunk
end

describe VirtualTime do
  it "can be initialized" do
    vt = VirtualTime.new
    vt.year.should be_nil
    vt.month.should be_nil
    vt.day.should be_nil
    vt.day_of_week.should be_nil
    vt.location.should be_nil
  end

  it "supports all documented types of values" do
    vt = VirtualTime.new
    vt.year = nil # Remains unspecified, matches everything it is compared with
    vt.month = 3
    vt.week = true
    vt.day = [1, 2]
    vt.hour = (10..20)
    vt.minute = (10..20).step(2)
    vt.millisecond = ->(_val : Int32) { true }
  end

  it "can materialize" do
    vt = VirtualTime.new
    # year, month, day, week, day_of_week, day_of_year, hour, minute, second, millisecond, nanosecond, location
    vt.materialize(Time::UNIX_EPOCH).to_tuple.should eq({1970, 1, 1, nil, nil, nil, 0, 0, 0, nil, 0, nil})
  end

  it "carries location and default_match over when materializing" do
    loc = Time::Location.load("Europe/Berlin")
    hint = Time.local 2023, 5, 10, location: loc

    vt = VirtualTime.new location: loc
    vt.materialize(hint).location.should eq loc

    # A `default_match?` of false needs every materialized field to be set,
    # otherwise the VT is not materializable at all.
    vt = VirtualTime.from_time hint
    vt.default_match = false
    vt.materialize(hint).default_match?.should be_false
  end

  it "honors strict when materializing" do
    vt = VirtualTime.new day: 15
    hint = Time.local 2023, 5, 10

    # Strict (the default) snaps the hint up to the earliest allowed value
    vt.materialize(hint).day.should eq 15
    # Non-strict keeps the hint's own value
    vt.materialize(hint, false).day.should eq 10
  end

  it "materializes respecting week and day_of_week constraints" do
    vt = VirtualTime.new
    vt.week = 1
    vt.day_of_week = 1 # Monday
    t = vt.to_time(Time.local 2023, 1, 1)
    t.calendar_week[1].should eq 1
    t.day_of_week.to_i.should eq 1
  end

  it "raises on materialize when rules are impossible" do
    vt = VirtualTime.new
    vt.week = 54
    vt.day_of_week = 1
    expect_raises(ArgumentError) do
      vt.to_time(Time.local 2023, 1, 1)
    end
  end

  it "can expand VTs" do
    d = VirtualTime.new
    d.year = 2017
    # d.month= 1..3
    d.day = 14..17
    d.hour = 9..12
    d.millisecond = 1
    d.expand.should eq [
      VirtualTime.new(2017, nil, 14, nil, nil, nil, 9, nil, nil, 1, nil, nil),
      VirtualTime.new(2017, nil, 14, nil, nil, nil, 10, nil, nil, 1, nil, nil),
      VirtualTime.new(2017, nil, 14, nil, nil, nil, 11, nil, nil, 1, nil, nil),
      VirtualTime.new(2017, nil, 14, nil, nil, nil, 12, nil, nil, 1, nil, nil),
      VirtualTime.new(2017, nil, 15, nil, nil, nil, 9, nil, nil, 1, nil, nil),
      VirtualTime.new(2017, nil, 15, nil, nil, nil, 10, nil, nil, 1, nil, nil),
      VirtualTime.new(2017, nil, 15, nil, nil, nil, 11, nil, nil, 1, nil, nil),
      VirtualTime.new(2017, nil, 15, nil, nil, nil, 12, nil, nil, 1, nil, nil),
      VirtualTime.new(2017, nil, 16, nil, nil, nil, 9, nil, nil, 1, nil, nil),
      VirtualTime.new(2017, nil, 16, nil, nil, nil, 10, nil, nil, 1, nil, nil),
      VirtualTime.new(2017, nil, 16, nil, nil, nil, 11, nil, nil, 1, nil, nil),
      VirtualTime.new(2017, nil, 16, nil, nil, nil, 12, nil, nil, 1, nil, nil),
      VirtualTime.new(2017, nil, 17, nil, nil, nil, 9, nil, nil, 1, nil, nil),
      VirtualTime.new(2017, nil, 17, nil, nil, nil, 10, nil, nil, 1, nil, nil),
      VirtualTime.new(2017, nil, 17, nil, nil, nil, 11, nil, nil, 1, nil, nil),
      VirtualTime.new(2017, nil, 17, nil, nil, nil, 12, nil, nil, 1, nil, nil),
    ]
  end

  it "can match Crystal's Times" do
    vt = VirtualTime.new

    vt.matches?(Time.local).should be_true

    vt.month = 3
    vt.day = (10..20).step(2)

    vt.matches?(Time.parse("2018-03-10", "%F", Time::Location::UTC)).should be_true
    vt.matches?(Time.parse("2018-03-11", "%F", Time::Location::UTC)).should be_false
  end

  it "can match other VirtualTimes" do
    vt = VirtualTime.new
    vt.year = 2017
    vt.month = 1..3
    vt.hour = [10, 11, 12]
    vt.minute = (10..30).step(3)
    vt.second = ->(_val : Int32) { true }
    vt.millisecond = 1

    vt2 = VirtualTime.new
    vt2.year = nil
    vt2.month = [2, 3]
    vt2.day = ->(_val : Int32) { true }
    vt2.hour = 11..12
    vt2.minute = 20..25
    vt2.second = 10
    vt2.millisecond = (10..30).step(3)

    vt.matches?(vt2).should be_false

    vt.millisecond = 16
    vt.matches?(vt2).should be_true
    vt.matches?(vt2).should be_true
  end

  it "can match Crystal's Times in different locations" do
    vt = VirtualTime.new
    vt.hour = 16..20

    t = Time.local 2023, 10, 10, hour: 0, location: Time::Location.load("Europe/Berlin")
    vt.matches?(t).should be_false

    vt.location = Time::Location.load("America/New_York")
    vt.matches?(t).should be_true
  end

  it "can #to_yaml and #from_yaml" do
    date = VirtualTime.new
    date.year = 2017
    date.month = 4..6
    date.hour = (2..8).step 3

    y = date.to_yaml
    date2 = VirtualTime.from_yaml y
    y.should eq date2.to_yaml

    date.hour = (2...10).step 3

    y = date.to_yaml
    date2 = VirtualTime.from_yaml y
    y.should eq date2.to_yaml
  end

  it "converts to YAML" do
    vt = VirtualTime.new
    vt.month = 3
    vt.day = [1, 2]
    vt.hour = (10..20)
    vt.minute = (10..20).step 2
    vt.second = true
    vt.location = Time::Location.load("Europe/Berlin")
    # vt.millisecond = ->( val : Int32) { true }
    vt.to_yaml.should eq "---\nmonth: 3\nday: 1,2\nhour: 10..20\nminute: 10..20/2\nsecond: true\nlocation: Europe/Berlin\ndefault_match: true\n"
  end

  it "serializes a stepped range without consuming it" do
    vt = VirtualTime.new
    vt.minute = (10..20).step 2

    # Regression: serializing used to iterate (and thereby exhaust) the
    # iterator, so any later use of the value saw an empty sequence.
    vt.to_yaml.should eq vt.to_yaml
    vt.matches?(Time.local 2023, 1, 1, 0, 12).should be_true

    # The step survives the round-trip, rather than degrading to a plain list
    vt2 = VirtualTime.from_yaml vt.to_yaml
    vt2.minute.should be_a Steppable::StepIterator(Int32, Int32, Int32)
    vt2.matches?(Time.local 2023, 1, 1, 0, 12).should be_true
    vt2.matches?(Time.local 2023, 1, 1, 0, 13).should be_false
  end

  it "serializes a wide stepped range compactly" do
    vt = VirtualTime.new
    # Listing the individual values would produce a ~100 MB document
    vt.nanosecond = (0..999_999_999).step 10
    vt.to_yaml.should eq "---\nnanosecond: 0..999999999/10\ndefault_match: true\n"
  end

  it "converts from YAML" do
    vt = VirtualTime.from_yaml "---\nmonth: 3\nday: 1,2\nhour: 10..20\nminute: 10,12,14,16,18,20\nsecond: true\nlocation: Europe/Berlin\ndefault_match: false\n"
    vt.month.should eq 3
    vt.day.should eq [1, 2]
    vt.hour.should eq 10..20
    vt.second.should be_true
    vt.location.should eq Time::Location.load("Europe/Berlin")
    vt.default_match?.should be_false
  end

  it "does range comparison properly" do
    vt = VirtualTime.new
    a = 6..10
    b = 2..4
    c = 4..6
    d = 6..8
    e = 5..7
    f = 7..8
    g = 8..10
    h = 10..12
    i = 9..11
    j = 20..24
    vt.matches?(a, b).should be_false
    vt.matches?(a, c).should be_true
    vt.matches?(a, d).should be_true
    vt.matches?(a, e).should be_true
    vt.matches?(a, f).should be_true
    vt.matches?(a, g).should be_true
    vt.matches?(a, h).should be_true
    vt.matches?(a, i).should be_true
    vt.matches?(a, j).should be_false
  end

  # Other

  it "respects default_match?" do
    vt = VirtualTime.new
    vt.matches?(Time.local).should be_true
    vt.default_match = false
    vt.matches?(Time.local).should be_false
  end

  it "respects default_match only for nil fields" do
    vt = VirtualTime.new
    vt.hour = 10
    vt.matches?(Time.local 2023, 1, 1, 10).should be_true
    vt.matches?(Time.local 2023, 1, 1, 11).should be_false
  end

  it "can adjust timezone for Times" do
    time = Time.local year: 2020, month: 1, day: 15, location: Time::Location.load("Europe/Berlin")
    vt = VirtualTime.new location: Time::Location.load("America/New_York")
    time2 = vt.adjust_location time
    time2.should eq time.in Time::Location.load("America/New_York")
  end

  it "raises when matching VTs with different locations" do
    vt = VirtualTime.new location: Time::Location.load("Europe/Berlin")
    vt2 = VirtualTime.new location: Time::Location.load("America/New_York")

    expect_raises(ArgumentError) do
      vt.adjust_location vt2
    end

    expect_raises(ArgumentError) do
      vt.matches?(vt2)
    end
  end

  it "Handles comparisons with Time" do
    vt = VirtualTime.new
    t = Time.local
    (vt == t).should be_true
    (vt <=> t).should eq 0
    vt.year = 1970
    (vt == t).should be_false
    (vt <=> t).should be_nil
  end

  it "does not order against Times (only equality is meaningful)" do
    vt = VirtualTime.new
    t = Time.local

    # A match compares as equal, so strict ordering is false:
    (vt < t).should be_false
    (vt > t).should be_false
    (vt <= t).should be_true
    (vt >= t).should be_true

    # A non-match has no defined ordering, so all ordering operators are false:
    vt.year = 1970
    (vt < t).should be_false
    (vt > t).should be_false
    (vt <= t).should be_false
    (vt >= t).should be_false
  end

  it "#to_time preserves time-of-day when anchoring by week and day_of_week" do
    loc = Time::Location.load("Europe/Berlin")
    t = Time.local(2023, 5, 10, 10, 0, location: loc)
    # A from_time VT has both week and day_of_week set, triggering the
    # ISO-week anchoring path in #to_time.
    vt = VirtualTime.from_time(t)

    vt.to_time(t.at_beginning_of_day).should eq t
    # Hint in January: the anchor walk crosses a DST boundary (2023-03-26),
    # which must not disturb the materialized time part.
    vt.to_time(Time.local(2023, 1, 1, location: loc)).should eq t
  end

  it "#to_time materializes a day that the hint's own month cannot hold" do
    utc = Time::Location::UTC

    # Regression: `day` was sized by the hint's month, so a hint in February
    # produced February 31 and `Time.local` raised
    vt = VirtualTime.new day: 31, hour: 0, minute: 0, second: 0, nanosecond: 0
    vt.to_time(Time.local(2024, 2, 28, location: utc)).should eq Time.local(2024, 3, 31, location: utc)

    # A day that only some Februaries hold, reached from a non-leap year
    vt = VirtualTime.new month: 2, day: 29, hour: 0, minute: 0, second: 0, nanosecond: 0
    vt.to_time(Time.local(2023, 1, 1, location: utc)).should eq Time.local(2024, 2, 29, location: utc)

    # A negative day counts from the end of the month it lands in, not the hint's
    vt = VirtualTime.new month: 2, day: -1, hour: 0, minute: 0, second: 0, nanosecond: 0
    vt.to_time(Time.local(2023, 1, 1, location: utc)).should eq Time.local(2023, 2, 28, location: utc)

    # A day no month ever holds stays an error
    vt = VirtualTime.new month: 4, day: 31
    expect_raises(ArgumentError) { vt.to_time(Time.local(2023, 1, 1, location: utc)) }
  end

  it "materializes a `day` counted from the end of the month it lands in" do
    utc = Time::Location::UTC

    # Regression: the day was sized by the hint's month and kept even when the
    # month then carried forward, so it named a real but wrong day -- `-26` is
    # the 6th of a 31-day month but the 3rd of a 28-day one
    vt = VirtualTime.new day: -26, hour: 0, minute: 0, second: 0, nanosecond: 0
    vt.succ(Time.local(2022, 1, 18, location: utc)).should eq Time.local(2022, 2, 3, location: utc)

    # Every month in turn, each with its own last-but-one day
    vt = VirtualTime.new day: -2, hour: 0, minute: 0, second: 0, nanosecond: 0
    t = Time.local(2023, 1, 31, location: utc)
    [Time.local(2023, 2, 27, location: utc), Time.local(2023, 3, 30, location: utc), Time.local(2023, 4, 29, location: utc)].each do |expected|
      t = vt.succ t
      t.should eq expected
    end
  end

  it "counts weeks per ISO year rather than per weekday asked about" do
    utc = Time::Location::UTC

    # Regression: `weeks_in_year` mixed the last day of the year's ordinal with
    # the *queried* date's day of week, so the same year reported 52 or 53
    # depending on which date it was asked about
    {2020 => 53, 2021 => 52}.each do |year, weeks|
      (1..12).each do |month|
        VirtualTime::TimeHelper.weeks_in_year(Time.local(year, month, 15, location: utc)).should eq weeks
      end
    end

    # So `week: -1` covers exactly the seven days of the year's last ISO week
    vt = VirtualTime.new week: -1
    start = Time.local(2019, 12, 20, location: utc)
    matched = (0...16).map { |offset| start.shift(days: offset) }.select { |time| vt.matches? time }
    matched.size.should eq 7
    matched.first.should eq Time.local(2019, 12, 23, location: utc)
    matched.map { |time| time.calendar_week[1] }.uniq!.should eq [52]
  end

  it "materializes a `millisecond` requirement into the nanosecond" do
    utc = Time::Location::UTC
    hint = Time.local(2023, 1, 1, location: utc)

    # Regression: `millisecond` was matched but never materialized -- a `Time`
    # has no millisecond of its own, so the rule could not be satisfied and
    # `#to_time` produced a value the VirtualTime did not match
    vt = VirtualTime.new millisecond: 500
    t = vt.to_time hint
    t.nanosecond.should eq 500_000_000
    vt.matches?(t).should be_true

    # Moving the millisecond leaves the finer part behind it at zero, and
    # carries into the second when it has to wrap
    vt = VirtualTime.new millisecond: [0, 500], second: 0
    vt.to_time(Time.local(2023, 1, 1, 0, 0, 0, nanosecond: 250_000_123, location: utc))
      .should eq Time.local(2023, 1, 1, 0, 0, 0, nanosecond: 500_000_000, location: utc)
  end

  it "#succ never returns a time at or before the one asked for" do
    utc = Time::Location::UTC

    # Regression: the ISO-week anchor was computed within the hint's own year,
    # so a target week already behind the hint produced a time in the past
    vt = VirtualTime.new week: 10, day_of_week: 3, hour: 0, minute: 0, second: 0, nanosecond: 0
    vt.succ(Time.local(2023, 5, 10, 13, 37, location: utc)).should eq Time.local(2024, 3, 6, location: utc)

    vt = VirtualTime.new week: 1, day_of_week: 1, hour: 0, minute: 0, second: 0, nanosecond: 0
    vt.succ(Time.local(2020, 12, 28, location: utc)).should eq Time.local(2021, 1, 4, location: utc)

    # A week without a day of week lands on a day of that week, going forward
    vt = VirtualTime.new week: 29, day: 18, hour: 0, minute: 0, second: 0, nanosecond: 0
    vt.succ(Time.local(2023, 1, 26, 14, 51, location: utc)).should eq Time.local(2023, 7, 18, location: utc)
  end

  it "#to_time keeps searching past a day that a single day step cannot reach" do
    utc = Time::Location::UTC

    # Regression: the retry loop advanced one day at a time without
    # re-materializing, so 100 attempts fell far short of the next December 25
    # that is a Friday
    vt = VirtualTime.new month: 12, day: 25, day_of_week: 5, hour: 0, minute: 0, second: 0, nanosecond: 0
    vt.succ(Time.local(2023, 1, 1, location: utc)).should eq Time.local(2026, 12, 25, location: utc)
  end

  it "#to_time keeps the time of day across a DST transition" do
    ny = Time::Location.load("America/New_York")

    # Regression: days were added as an exact `Time::Span`, so a walk over the
    # DST forward transition moved the wall clock out of the wanted hour
    vt = VirtualTime.new day_of_week: 1, hour: 2..4, minute: 0, second: 0, nanosecond: 0
    t = vt.succ(Time.local(2022, 11, 4, location: ny))
    vt.matches?(t).should be_true
    t.should eq Time.local(2022, 11, 7, 2, 0, location: ny)

    # A time of day inside the spring-forward gap does not exist on that date,
    # so the next date that does have it is used
    vt = VirtualTime.new hour: 2, minute: 30, second: 0, nanosecond: 0
    t = vt.succ(Time.local(2023, 3, 12, 0, 0, location: ny))
    vt.matches?(t).should be_true
    t.should eq Time.local(2023, 3, 13, 2, 30, location: ny)
  end

  it "anchors a week within the ISO year, not the calendar one" do
    utc = Time::Location::UTC

    # Regression: the anchor started from the calendar year while the week
    # number counts within the ISO year, so any date whose two years differ --
    # the first days of January, the last of December -- was a year out and
    # could not be resolved at all
    [Time.local(2021, 1, 1, location: utc), Time.local(2021, 1, 3, location: utc),
     Time.local(2019, 12, 30, location: utc), Time.local(2023, 1, 1, location: utc)].each do |time|
      VirtualTime.from_time(time).to_time(time).should eq time
    end

    # The README's own example: week 53 of 2026 ends on January 3 2027
    vt = VirtualTime.new week: 53, day_of_week: 7, hour: 0, minute: 0, second: 0, nanosecond: 0
    resolved = vt.succ(Time.local(2026, 6, 1, location: utc))
    resolved.should eq Time.local(2027, 1, 3, location: utc)
    resolved.calendar_week.should eq({2026, 53})
  end

  it "materializes in its own location, whatever zone the hint is in" do
    berlin = Time::Location.load("Europe/Berlin")
    utc = Time::Location::UTC

    vt = VirtualTime.new hour: 10, minute: 0, second: 0, nanosecond: 0, location: berlin
    hint = Time.local(2023, 5, 10, 0, 0, 0, location: utc)

    # Regression: field values are read in the VirtualTime's own location by
    # `#matches?` but were materialized in the hint's, so 10:00 UTC came out --
    # a time that is 12:00 in Berlin and so does not match at all
    t = vt.to_time hint
    t.should eq Time.local(2023, 5, 10, 10, 0, location: berlin)
    vt.matches?(t).should be_true

    vt.materialize(hint).hour.should eq 10

    # Without a location of its own the hint's zone still propagates
    plain = VirtualTime.new hour: 10, minute: 0, second: 0, nanosecond: 0
    plain.to_time(hint).location.should eq utc
  end

  it "hashes consistently with #==" do
    vt = VirtualTime.new month: 3, day: [1, 2], hour: 10..12
    same = VirtualTime.new month: 3, day: [1, 2], hour: 10..12

    # Regression: `#==` was overridden without `#hash`, so equal VirtualTimes
    # landed in different buckets and a `Set` kept both of them
    (vt == same).should be_true
    vt.hash.should eq same.hash
    Set{vt, same}.size.should eq 1
    {vt => :marker}[same]?.should eq :marker

    VirtualTime.new(hour: 10..12).hash.should_not eq VirtualTime.new(hour: 10...12).hash
  end

  it "rejects a #step that would not advance" do
    vt = VirtualTime.new minute: 0, second: 0, nanosecond: 0

    # Regression: these produced an iterator that handed back the same Time
    # forever, or -- for a negative interval -- walked backwards
    expect_raises(ArgumentError, /interval must be positive/) { vt.step(0.seconds) }
    expect_raises(ArgumentError, /interval must be positive/) { vt.step(-1.hour) }
    expect_raises(ArgumentError, /`by` must be positive/) { vt.step(1.hour, 0) }
  end

  it "refuses to materialize a value that allows nothing" do
    hint = Time.local(2023, 1, 1, location: Time::Location::UTC)

    # Regression: an empty range materialized to its `begin`, handing back a
    # Time the VirtualTime does not match
    expect_raises(ArgumentError, /empty range/) do
      VirtualTime.new(hour: 5...5).to_time hint
    end

    expect_raises(ArgumentError, /empty list/) do
      VirtualTime.new(hour: [] of Int32).to_time hint
    end
  end

  it "keeps a `false` field through a YAML round-trip" do
    vt = VirtualTime.new hour: false, minute: 5

    # Regression: `YAML::Serializable` tests a converter-backed property for
    # truthiness, so `false` ("never match") was written out as null and read
    # back as nil ("match anything")
    vt.to_yaml.should contain "hour: false"
    VirtualTime.from_yaml(vt.to_yaml).hour.should be_false
  end

  it "raises when deserializing a Proc from YAML" do
    expect_raises(ArgumentError, /Procs cannot be deserialized/) do
      VirtualTime.from_yaml %(---\nhour: "->(v : Int32) { true }"\n)
    end
  end

  it "matches?(Nil, any, max)" do
    vt = VirtualTime.new
    {nil, 0, 1, 1000}.each do |max|
      vt.matches?(nil, nil, max).should be_true
      vt.matches?(nil, false, max).should be_false
      vt.matches?(nil, true, max).should be_true
      vt.matches?(nil, 0, max).should be_true
      vt.matches?(nil, 15, max).should be_true
      vt.matches?(nil, [1, 2, 3], max).should be_true
      vt.matches?(nil, 1..10, max).should be_true
      vt.matches?(nil, (1..10).step(3), max).should be_true
      vt.matches?(nil, ->(_val : Int32) { false }, max).should be_true
    end
  end

  it "matches?(Bool, any, max)" do
    vt = VirtualTime.new
    {nil, 0, 1, 1000}.each do |max|
      vt.matches?(true, nil, max).should be_true
      vt.matches?(true, false, max).should be_false
      vt.matches?(true, true, max).should be_true
      vt.matches?(true, 0, max).should be_true
      vt.matches?(true, 15, max).should be_true
      vt.matches?(true, [1, 2, 3], max).should be_true
      vt.matches?(true, 1..10, max).should be_true
      vt.matches?(true, (1..10).step(3), max).should be_true
      vt.matches?(true, ->(_val : Int32) { false }, max).should be_true

      vt.matches?(false, nil, max).should be_false
      vt.matches?(false, false, max).should be_false
      vt.matches?(false, true, max).should be_false
      vt.matches?(false, 0, max).should be_false
      vt.matches?(false, 15, max).should be_false
      vt.matches?(false, [1, 2, 3], max).should be_false
      vt.matches?(false, 1..10, max).should be_false
      vt.matches?(false, (1..10).step(3), max).should be_false
      vt.matches?(false, ->(_val : Int32) { false }, max).should be_false
    end
  end

  it "matches?(Int, Int, max)" do
    vt = VirtualTime.new
    max = nil
    vt.matches?(9, 13, max).should be_false
    vt.matches?(9, 1, max).should be_false
    vt.matches?(9, 9, max).should be_true
    vt.matches?(9, 0, max).should be_false
    vt.matches?(9, 31, max).should be_false
    vt.matches?(5, -5, max).should be_false
    vt.matches?(-5, -5, max).should be_true
    vt.matches?(-5, 5, max).should be_false
    vt.matches?(6, -5, max).should be_false
    vt.matches?(5, -6, max).should be_false
    vt.matches?(0, 0, max).should be_true

    max = 10
    vt.matches?(9, 13, max).should be_false
    vt.matches?(9, 1, max).should be_false
    vt.matches?(9, 9, max).should be_true
    vt.matches?(9, 0, max).should be_false
    vt.matches?(9, 31, max).should be_false
    vt.matches?(5, -5, max).should be_true
    vt.matches?(-5, -5, max).should be_true
    vt.matches?(-5, 5, max).should be_true
    vt.matches?(6, -5, max).should be_false
    vt.matches?(5, -6, max).should be_false
    vt.matches?(max, max, max).should be_true
    vt.matches?(-max, max, max).should be_false
    vt.matches?(max, -max, max).should be_false
    vt.matches?(-max, -max, max).should be_true
  end

  it "matches?(Array(Int), Int, max)" do
    vt = VirtualTime.new
    max = nil
    vt.matches?([9], 13, max).should be_false
    vt.matches?([9], 1, max).should be_false
    vt.matches?([9], 9, max).should be_true
    vt.matches?([9], 0, max).should be_false
    vt.matches?([9], 31, max).should be_false
    vt.matches?([5], -5, max).should be_false
    vt.matches?([-5], -5, max).should be_true
    vt.matches?([-5], 5, max).should be_false
    vt.matches?([6], -5, max).should be_false
    vt.matches?([5], -6, max).should be_false
    vt.matches?([0], 0, max).should be_true

    max = 10
    vt.matches?([9], 13, max).should be_false
    vt.matches?([9], 1, max).should be_false
    vt.matches?([9], 9, max).should be_true
    vt.matches?([9], 0, max).should be_false
    vt.matches?([9], 31, max).should be_false
    vt.matches?([5], -5, max).should be_true
    vt.matches?([-5], -5, max).should be_true
    vt.matches?([-5], 5, max).should be_true
    vt.matches?([6], -5, max).should be_false
    vt.matches?([5], -6, max).should be_false
    vt.matches?([max], max, max).should be_true
    vt.matches?([-max], max, max).should be_false
    vt.matches?([max], -max, max).should be_false
    vt.matches?([-max], -max, max).should be_true

    max = nil
    vt.matches?([1, 9], 13, max).should be_false
    vt.matches?([1, 9], 1, max).should be_true
    vt.matches?([9], 9, max).should be_true
    vt.matches?([9], 0, max).should be_false
    vt.matches?([9], 31, max).should be_false
    vt.matches?([5], -5, max).should be_false
    vt.matches?([-5], -5, max).should be_true
    vt.matches?([-5], 5, max).should be_false
    vt.matches?([6, -5], -5, max).should be_true
    vt.matches?([5], -6, max).should be_false
    vt.matches?([0], 0, max).should be_true

    max = 10
    vt.matches?([9], 13, max).should be_false
    vt.matches?([9], 1, max).should be_false
    vt.matches?([9], 9, max).should be_true
    vt.matches?([9], 0, max).should be_false
    vt.matches?([9], 31, max).should be_false
    vt.matches?([5], -5, max).should be_true
    vt.matches?([-5], -5, max).should be_true
    vt.matches?([-5], 5, max).should be_true
    vt.matches?([6], -5, max).should be_false
    vt.matches?([5], -6, max).should be_false
    vt.matches?([max], max, max).should be_true
    vt.matches?([-max], max, max).should be_false
    vt.matches?([max], -max, max).should be_false
    vt.matches?([-max], -max, max).should be_true
  end

  it "matches?(Range(Int, Int), Int, max)" do
    vt = VirtualTime.new
    max = nil
    vt.matches?(1..8, -1, max).should be_false
    vt.matches?(1..8, 0, max).should be_false
    vt.matches?(1..8, 1, max).should be_true
    vt.matches?(1..8, -5, max).should be_false
    vt.matches?(1..8, 5, max).should be_true
    vt.matches?(1..8, 8, max).should be_true
    vt.matches?(1..8, 9, max).should be_false
    vt.matches?(1..8, -8, max).should be_false
    vt.matches?(1..8, -7, max).should be_false
    vt.matches?(1..8, -9, max).should be_false
    vt.matches?(1..8, 13, max).should be_false

    max = 8
    vt.matches?(1..8, -1, max).should be_true
    vt.matches?(1..8, 0, max).should be_false
    vt.matches?(1..8, 1, max).should be_true
    vt.matches?(1..8, -5, max).should be_true
    vt.matches?(1..8, 5, max).should be_true
    vt.matches?(1..8, 8, max).should be_true
    vt.matches?(1..8, 9, max).should be_false
    vt.matches?(1..8, -8, max).should be_false
    vt.matches?(1..8, -7, max).should be_true
    vt.matches?(1..8, -9, max).should be_false
    vt.matches?(1..8, 13, max).should be_false
  end

  it "matches?(Steppable(Int, Int), Int, max)" do
    vt = VirtualTime.new
    max = nil
    vt.matches?((1..8).step(2), -1, max).should be_false
    vt.matches?((1..8).step(2), 0, max).should be_false
    vt.matches?((1..8).step(2), 1, max).should be_true
    vt.matches?((1..8).step(2), -5, max).should be_false
    vt.matches?((1..8).step(2), 5, max).should be_true
    vt.matches?((1..8).step(2), 8, max).should be_false
    vt.matches?((1..8).step(2), 9, max).should be_false
    vt.matches?((1..8).step(2), -8, max).should be_false
    vt.matches?((1..8).step(2), -7, max).should be_false
    vt.matches?((1..8).step(2), -9, max).should be_false
    vt.matches?((1..8).step(2), 13, max).should be_false

    max = 8
    vt.matches?((1..8).step(2), -1, max).should be_true
    vt.matches?((1..8).step(2), 0, max).should be_false
    vt.matches?((1..8).step(2), 1, max).should be_true
    vt.matches?((1..8).step(2), -5, max).should be_true
    vt.matches?((1..8).step(2), 5, max).should be_true
    vt.matches?((1..8).step(2), 8, max).should be_false
    vt.matches?((1..8).step(2), 9, max).should be_false
    vt.matches?((1..8).step(2), -8, max).should be_false
    vt.matches?((1..8).step(2), -7, max).should be_true
    vt.matches?((1..8).step(2), -9, max).should be_false
    vt.matches?((1..8).step(2), 13, max).should be_false
  end

  # Enumerable not tested directly

  it "matches?(Array(Int), Array(Int), max)" do
    vt = VirtualTime.new
    max = nil
    vt.matches?([9], [1], max).should be_false
    vt.matches?([9], [1, 2, 3, 4, 8, 10, 11], max).should be_false
    vt.matches?([9], [9], max).should be_true
    vt.matches?([9], [-1, -8, -9, -10], max).should be_false
    vt.matches?([9], [0], max).should be_false
    vt.matches?([5], [-5], max).should be_false
    vt.matches?([-5], [-5], max).should be_true
    vt.matches?([-5], [5], max).should be_false
    vt.matches?([6], [-1], max).should be_false
    vt.matches?([0], [-1, 0, 1], max).should be_true

    max = 10
    vt.matches?([9], [1], max).should be_false
    vt.matches?([9], [1, 2, 3, 4, 8, 10, 11], max).should be_false
    vt.matches?([9], [9], max).should be_true
    vt.matches?([9], [-1, -8, -9, -10], max).should be_true
    vt.matches?([9], [0], max).should be_false
    vt.matches?([5], [-5], max).should be_true
    vt.matches?([-5], [-5], max).should be_true
    vt.matches?([-5], [5], max).should be_true
    vt.matches?([6], [-1], max).should be_false
    vt.matches?([0], [-1, 0, 1], max).should be_true
  end

  it "matches?(Range(Int,Int), Range(Int,Int), max)" do
    vt = VirtualTime.new
    max = nil
    vt.matches?(10..23, 1..30, max).should be_true
    vt.matches?(10..23, 1..10, max).should be_true
    vt.matches?(10..23, 23..30, max).should be_true
    vt.matches?(10..23, 5..9, max).should be_false
    vt.matches?(10..23, 24..30, max).should be_false
    vt.matches?(10..23, 1..12, max).should be_true
    vt.matches?(10..23, 21..30, max).should be_true
    vt.matches?(1..5, 6..10, max).should be_false
    vt.matches?(6..10, 1..5, max).should be_false
    vt.matches?(10..-1, 15..20, max).should be_false
    vt.matches?(1..-10, 5..-15, max).should be_false

    max = 30
    vt.matches?(10..23, 1..30, max).should be_true
    vt.matches?(10..23, 1..10, max).should be_true
    vt.matches?(10..23, 23..30, max).should be_true
    vt.matches?(10..23, 5..9, max).should be_false
    vt.matches?(10..23, 24..30, max).should be_false
    vt.matches?(10..23, 1..12, max).should be_true
    vt.matches?(10..23, 21..30, max).should be_true
    vt.matches?(1..5, 6..10, max).should be_false
    vt.matches?(6..10, 1..5, max).should be_false
    vt.matches?(10..-1, 15..20, max).should be_true
    vt.matches?(1..-10, 5..-15, max).should be_true
    vt.matches?(1..-1, 10..-10, max).should be_true
    vt.matches?(1..-1, 40..50, max).should be_false
  end

  it "matches?(Steppable::StepIterator(Int,Int,Int), Int, max)" do
    vt = VirtualTime.new
    max = nil
    vt.matches?((10..23).step(2), 10, max).should be_true
    vt.matches?((10..23).step(2), 11, max).should be_false
    vt.matches?((10..23).step(2), 22, max).should be_true
    vt.matches?((10..23).step(3), 23, max).should be_false
    vt.matches?((10..23).step(2), 9, max).should be_false
    vt.matches?((10..23).step(2), 24, max).should be_false
    vt.matches?((1..5).step(2), -28, max).should be_false
    vt.matches?((6..10).step(2), 3, max).should be_false
    vt.matches?((10..-1).step(2), 20, max).should be_false
    vt.matches?((1..-10).step(2), 2, max).should be_false

    max = 30
    vt.matches?((10..23).step(2), 10, max).should be_true
    vt.matches?((10..23).step(2), 11, max).should be_false
    vt.matches?((10..23).step(2), 22, max).should be_true
    vt.matches?((10..23).step(3), 23, max).should be_false
    vt.matches?((10..23).step(2), 9, max).should be_false
    vt.matches?((10..23).step(2), 24, max).should be_false
    vt.matches?((1..5).step(3), -26, max).should be_true
    vt.matches?((6..10).step(2), 3, max).should be_false
    vt.matches?((10..-1).step(2), 20, max).should be_true
    vt.matches?((1..-10).step(2), 2, max).should be_false
    vt.matches?((10..-1).step(2), 0, max).should be_false
    vt.matches?((2..-10).step(2), 0, max).should be_false
    vt.matches?((1..-1).step(7), 6, max).should be_false
    vt.matches?((1..-1).step(6), 7, max).should be_true
    vt.matches?((1..-1).step(7), 15, max).should be_true
  end

  it "matches?(Steppable::StepIterator(Int,Int,Int), Steppable::StepIterator(Int,Int,Int), max)" do
    vt = VirtualTime.new
    max = nil
    vt.matches?((10..23).step(2), (10..23).step(2), max).should be_true
    vt.matches?((10..23).step(2), (10..23).step(3), max).should be_true
    vt.matches?((10..23).step(2), (11..23).step(2), max).should be_false
    vt.matches?((10..23).step(3), (5..10).step(2), max).should be_false
    vt.matches?((10..23).step(2), (6..10).step(2), max).should be_true
    vt.matches?((10..23).step(2), (10..23).step(2), max).should be_true
    vt.matches?((1..5).step(2), (10..23).step(2), max).should be_false
    vt.matches?((6..10).step(2), (10..23).step(2), max).should be_true
    vt.matches?((10..-1).step(2), (10..23).step(2), max).should be_false
    vt.matches?((1..-10).step(2), (10..23).step(2), max).should be_false

    max = 30
    vt.matches?((10..23).step(2), (10..23).step(2), max).should be_true
    vt.matches?((10..23).step(2), (10..23).step(3), max).should be_true
    vt.matches?((10..23).step(2), (11..23).step(2), max).should be_false
    vt.matches?((10..23).step(3), (5..10).step(2), max).should be_false
    vt.matches?((10..23).step(2), (6..10).step(2), max).should be_true
    vt.matches?((10..23).step(2), (10..23).step(2), max).should be_true
    vt.matches?((1..5).step(2), (10..23).step(2), max).should be_false
    vt.matches?((6..10).step(2), (10..23).step(2), max).should be_true
    vt.matches?((10..-1).step(2), (16..23).step(2), max).should be_true
    vt.matches?((10..-1).step(2), (17..23).step(2), max).should be_false
    vt.matches?((1..-10).step(2), (-20..-10).step(2), max).should be_false
    vt.matches?((1..-10).step(3), (-25..-10).step(2), max).should be_true
    vt.matches?((2..-10).step(2), (40..-10).step(2), max).should be_false
    vt.matches?((-20..-1).step(2), (40..50).step(3), max).should be_false
    vt.matches?((1..-1).step(6), (5..23).step(2), max).should be_true
    vt.matches?((1..-1).step(7), (5..23).step(2), max).should be_true
  end

  it "matches?(VirtualProc, Int, max)" do
    vt = VirtualTime.new
    v_true = ->(_v : Int32) { true }
    v_false = ->(_v : Int32) { false }
    v_ge_10 = ->(v : Int32) { v >= 10 }

    vt.matches?(v_true, 0, nil).should be_true
    vt.matches?(v_false, 0, nil).should be_false
    vt.matches?(v_ge_10, 0, nil).should be_false
    vt.matches?(v_ge_10, 20, nil).should be_true
  end

  it "can't do matches?(VirtualProc, VirtualProc, max)" do
    vt = VirtualTime.new
    v_true = ->(_v : Int32) { true }
    expect_raises(ArgumentError) do
      vt.matches? v_true, v_true
    end
  end

  it "does not support Proc serialization to YAML" do
    vt = VirtualTime.new
    vt.second = ->(v : Int32) { v > 10 }
    expect_raises(Exception) do
      vt.to_yaml
    end
    # vt2 = VirtualTime.from_yaml yaml
    # vt2.second.should be_a(Proc(Int32, Bool))
    # vt2.matches?(Time.local).should be_true # placeholder proc always true
  end

  it "respects exclusive ranges in matching" do
    vt = VirtualTime.new
    vt.hour = 10...12

    vt.matches?(Time.local 2023, 1, 1, 10).should be_true
    vt.matches?(Time.local 2023, 1, 1, 11).should be_true
    vt.matches?(Time.local 2023, 1, 1, 12).should be_false
  end

  it "raises when wanted exceeds single wrap limit" do
    vt = VirtualTime.new
    expect_raises(ArgumentError) do
      vt.materialize(nil, 120, 0, 60)
    end
  end

  it "handles empty arrays and ranges safely" do
    vt = VirtualTime.new
    vt.matches?([] of Int32, 5, nil).should be_false
    vt.matches?(5, [] of Int32, nil).should be_false
    vt.matches?((1...1), 1, nil).should be_false
  end

  it "preserves range exclusivity when converting negative bounds" do
    vt = VirtualTime.new
    # `10...-1` with max 31 becomes `10...30` (exclusive), so 30 must not match
    vt.matches?(10...(-1), 30, 31).should be_false
    vt.matches?(10...(-1), 29, 31).should be_true
    # The inclusive counterpart `10..-1` => `10..30` does match 30
    vt.matches?(10..(-1), 30, 31).should be_true
  end

  it "matches large ranges via O(1) membership" do
    vt = VirtualTime.new
    # Regression: this used to iterate the whole range (O(n))
    vt.matches?(0..999_999_999, 500_000_000, 1_000_000_000).should be_true
    vt.matches?(0...999_999_999, 999_999_999, 1_000_000_000).should be_false
  end

  it "intersects two large ranges without iterating them" do
    vt = VirtualTime.new
    # Regression: both sides used to be iterated, i.e. O(n*m)
    vt.matches?(0..999_999_999, 500_000_000..600_000_000, 1_000_000_000).should be_true
    vt.matches?(0..1_000, 500_000..600_000, 1_000_000_000).should be_false

    # Exclusive bounds are respected on both sides
    vt.matches?(0..10, 10..20, nil).should be_true
    vt.matches?(0...10, 10..20, nil).should be_false
    vt.matches?(0..10, 10...20, nil).should be_true
    vt.matches?(0..10, (-1)...0, nil).should be_false

    # A range that contains no values matches nothing
    vt.matches?(1...1, 0..5, nil).should be_false
    vt.matches?(0..5, 1...1, nil).should be_false
  end

  it "tests list members against a large range rather than iterating it" do
    vt = VirtualTime.new
    vt.matches?(0..999_999_999, [1_500_000_000, 500_000_000], nil).should be_true
    vt.matches?(0..999_999_999, [1_500_000_000], nil).should be_false
    vt.matches?([1_500_000_000], 0..999_999_999, nil).should be_false
    vt.matches?([500_000_000], 0..999_999_999, nil).should be_true
    vt.matches?(0..999_999_999, (0..999_999_999).step(250_000_000), nil).should be_true
    vt.matches?(0..999_999_999, Set{1_500_000_000, 500_000_000}, nil).should be_true
  end

  it "generates successive matching times via #succ" do
    vt = VirtualTime.new
    vt.hour = 10
    vt.minute = 30
    t = vt.succ(Time.local 2023, 1, 1, 9, 0, 0)
    t.hour.should eq 10
    t.minute.should eq 30
    t.should be > Time.local(2023, 1, 1, 9, 0, 0)
  end

  it "iterates matching times via #step" do
    vt = VirtualTime.new
    vt.minute = 0
    it = vt.step(1.hour, 1, Time.local(2023, 1, 1, 0, 0, 0))
    times = Array(Time).new(3) { it.next.as(Time) }
    times.map(&.hour).should eq [0, 1, 2]
    times.all?(&.minute.==(0)).should be_true
  end

  it "creates a VirtualTime from a Time via .from_time" do
    t = Time.local(2023, 3, 15, 14, 30, 45, location: Time::Location::UTC)
    vt = VirtualTime.from_time(t)
    vt.year.should eq 2023
    vt.month.should eq 3
    vt.day.should eq 15
    vt.day_of_week.should eq 3
    vt.day_of_year.should eq 74
    vt.hour.should eq 14
    vt.minute.should eq 30
    vt.second.should eq 45
    vt.nanosecond.should eq 0    # nanoseconds copied by default
    vt.millisecond.should be_nil # milliseconds not copied by default
    vt.matches?(t).should be_true
  end

  it "clears fields via clear!, clear_date! and clear_time!" do
    t = Time.local(2023, 3, 15, 14, 30, 45, location: Time::Location::UTC)

    vt = VirtualTime.from_time(t)
    vt.clear_date!
    vt.year.should be_nil
    vt.day.should be_nil
    vt.hour.should eq 14 # time part untouched

    vt = VirtualTime.from_time(t)
    vt.clear_time!
    vt.hour.should be_nil
    vt.second.should be_nil
    vt.day.should eq 15 # date part untouched

    vt = VirtualTime.from_time(t)
    vt.clear!
    vt.to_tuple.should eq({nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil})
  end

  describe VirtualTime::Search do
    describe ".shift_from_base" do
      it "returns zero-based forward delta to first unblocked time" do
        t0 = Time.local(2023, 5, 10, 10, 0, 0)

        # Block exactly at t0, unblock at +2 minutes
        delta = VirtualTime::Search.shift_from_base(t0, 1.minute, max_shift: nil, max_shifts: 10) do |time|
          time <= t0 + 1.minute
        end

        delta.should eq VirtualTime::Result::Found.new 2.minutes
      end

      it "returns false when max_shifts is exceeded" do
        t0 = Time.local(2023, 5, 10, 10, 0, 0)

        delta = VirtualTime::Search.shift_from_base(t0, 1.minute, max_shift: nil, max_shifts: 2) do |_|
          true # always blocked
        end

        delta.should eq VirtualTime::Result::Blocked.new
      end

      it "returns false when max_shift window is exceeded" do
        t0 = Time.local(2023, 5, 10, 10, 0, 0)

        delta = VirtualTime::Search.shift_from_base(t0, 10.minutes, max_shift: 15.minutes, max_shifts: 10) do |_|
          true
        end

        delta.should eq VirtualTime::Result::OutOfBounds.new
      end

      it "handles DST transitions correctly" do
        loc = Time::Location.load("Europe/Berlin")
        # DST jump: 2023-03-26 02:00 -> 03:00
        t0 = Time.local(2023, 3, 26, 1, 30, 0, location: loc)

        delta = VirtualTime::Search.shift_from_base(t0, 1.hour, max_shift: 3.hours, max_shifts: 5) do |_|
          false
        end

        delta.should eq VirtualTime::Result::Found.new 1.hours
        (t0 + delta.as(VirtualTime::Result::Found).delta).hour.should eq 3
      end

      it "rejects zero-length step defensively" do
        t0 = Time.local(2023, 5, 10, 10, 0, 0)

        delta = VirtualTime::Search.shift_from_base(t0, 0.seconds, max_shift: 10.minutes, max_shifts: 10) do |_|
          false
        end

        delta.should eq VirtualTime::Result::InvalidStep.new
      end

      it "returns OutOfBounds when the candidate leaves the domain" do
        t0 = Time.local(2023, 5, 10, 10, 0, 0)

        # Always blocked, but the domain only permits the next 3 minutes,
        # so the search bails out once a candidate leaves the domain.
        result = VirtualTime::Search.shift_from_base(t0, 1.minute, domain: CutoffDomain.new(t0 + 3.minutes), max_shifts: 100) do |_|
          true
        end

        result.should eq VirtualTime::Result::OutOfBounds.new
      end

      it "finds a candidate within the domain" do
        t0 = Time.local(2023, 5, 10, 10, 0, 0)

        result = VirtualTime::Search.shift_from_base(t0, 1.minute, domain: CutoffDomain.new(t0 + 30.minutes), max_shift: 5.minutes) do |time|
          time < t0 + 2.minutes
        end

        result.should eq VirtualTime::Result::Found.new 2.minutes
      end
    end

    describe ".shifted_from_base?" do
      it "returns true when target is reachable via inverse shifting" do
        t0 = Time.local(2023, 5, 10, 10, 0, 0)
        target = t0 + 2.hours

        reachable = VirtualTime::Search.shifted_from_base?(target, 1.hour, max_shift: 3.hours, max_shifts: 5) do |base|
          # Base is considered schedulable but shifted by +2h
          if base == t0
            2.hours
          end
        end

        reachable.should be_true
      end

      it "returns false when inverse search exceeds bounds" do
        t0 = Time.local(2023, 5, 10, 10, 0, 0)
        target = t0 + 5.hours

        reachable = VirtualTime::Search.shifted_from_base?(target, 1.hour, max_shift: 2.hours, max_shifts: 10) do |base|
          # Only bases at least 5 hours away produce a shift,
          # which exceeds max_shift and must be rejected.
          if (target - base) >= 5.hours
            5.hours
          end
        end

        reachable.should be_false
      end

      it "returns true when inverse shift delta is exactly equal to max_shift" do
        t0 = Time.local(2023, 5, 10, 10, 0, 0)
        target = t0 + 2.hours

        reachable = VirtualTime::Search.shifted_from_base?(target, 1.hour, max_shift: 2.hours, max_shifts: 5) do |base|
          # Only the exact base produces the exact boundary delta.
          if base == t0
            2.hours
          end
        end

        reachable.should be_true
      end

      it "returns false when no base produces the target" do
        t0 = Time.local(2023, 5, 10, 10, 0, 0)
        target = t0 + 1.hour

        reachable = VirtualTime::Search.shifted_from_base?(target, 30.minutes, max_shift: 2.hours, max_shifts: 5) do |_|
          45.minutes
        end

        reachable.should be_false
      end

      it "returns true when inverse shift delta is exactly -max_shift (negative boundary)" do
        t0 = Time.local(2023, 5, 10, 10, 0, 0)
        target = t0 - 2.hours

        reachable = VirtualTime::Search.shifted_from_base?(target, -1.hour, max_shift: 2.hours, max_shifts: 5) do |base|
          # Only the exact base produces the exact negative boundary delta.
          if base == t0
            -2.hours
          end
        end

        reachable.should be_true
      end

      it "allows exact max_shift boundary across a DST transition" do
        loc = Time::Location.load("Europe/Berlin")

        # DST jump: 2023-03-26 02:00 -> 03:00
        base = Time.local(2023, 3, 26, 1, 30, 0, location: loc)

        # Two real hours later in absolute time, despite wall-clock jump
        target = base + 2.hours

        reachable = VirtualTime::Search.shifted_from_base?(target, 1.hour, max_shift: 2.hours, max_shifts: 5) do |candidate|
          if candidate == base
            2.hours
          end
        end

        reachable.should be_true
      end

      it "allows exact negative max_shift across a DST transition" do
        loc = Time::Location.load("Europe/Berlin")

        # DST jump: 2023-03-26 02:00 -> 03:00
        base = Time.local(2023, 3, 26, 3, 30, 0, location: loc)

        # Two real hours earlier in absolute time
        target = base - 2.hours

        reachable = VirtualTime::Search.shifted_from_base?(target, -1.hour, max_shift: 2.hours, max_shifts: 5) do |candidate|
          if candidate == base
            -2.hours
          end
        end

        reachable.should be_true
      end

      describe ".shift_from_base successor contract" do
        it "never returns a zero-length delta (successor semantics)" do
          base = Time.local(2023, 5, 10, 10, 0, 0)

          result = VirtualTime::Search.shift_from_base(base, 1.minute, max_shift: 10.minutes, max_shifts: 10) do |_|
            false # never blocked
          end

          case result
          when VirtualTime::Result::Found
            result.delta.should_not eq 0.seconds
          else
            fail "expected Result::Found, got #{result.class}"
          end
        end
      end

      it "never returns zero delta for negative steps either" do
        base = Time.local(2023, 5, 10, 10, 0, 0)

        result = VirtualTime::Search.shift_from_base(base, -1.minute, max_shift: 10.minutes, max_shifts: 10) do |_|
          false
        end

        result.as(VirtualTime::Result::Found).delta.should_not eq 0.seconds
      end
    end

    describe "property-style randomized Search invariants" do
      it "never returns true without a valid base producing the target" do
        rng = Random.new(54321)

        100.times do
          base = Time.local(2023, 5, 10, 12, 0, 0)
          target = base + rng.rand(-5..5).minutes

          step = rng.rand(1..3).minutes
          max_shift = 3.minutes
          max_shifts = 5

          reachable = VirtualTime::Search.shifted_from_base?(target, step, max_shift: max_shift, max_shifts: max_shifts) do |_|
            nil # No base ever produces a delta
          end

          reachable.should be_false
        end
      end

      it "never reports reachable unless a valid base produces the target within bounds" do
        rng = Random.new(12345)

        100.times do
          base = Time.local(2023, 5, 10, rng.rand(0..23), rng.rand(0..59), 0)

          step_minutes = rng.rand(-3..3)
          next if step_minutes == 0
          step = step_minutes.minutes

          delta_minutes = rng.rand(-5..5)
          delta = delta_minutes.minutes
          target = base + delta

          max_shift = 5.minutes
          max_shifts = 10

          reachable =
            VirtualTime::Search.shifted_from_base?(target, step, max_shift: max_shift, max_shifts: max_shifts) do |candidate|
              candidate == base ? delta : nil
            end

          if reachable
            # Soundness: reachable implies delta is valid
            delta.abs.should be <= max_shift
            (base + delta).should eq(target)
          end
        end
      end

      it "shift_from_base never exceeds max_shift and may fail due to step granularity" do
        rng = Random.new(999)

        100.times do
          start = Time.local(2023, 5, 10, 10, 0, 0)

          step_minutes = rng.rand(1..3)
          step = step_minutes.minutes

          blocked_for = rng.rand(0..5).minutes

          max_shift = 5.minutes
          max_shifts = 10

          delta = VirtualTime::Search.shift_from_base(start, step, max_shift: max_shift, max_shifts: max_shifts) do |time|
            time < start + blocked_for
          end

          case delta
          when Time::Span
            delta.abs.should be <= max_shift
          when Bool
            delta.should be_false
          end
        end
      end
    end
  end

  it "shrinks failing DST cases automatically" do
    rng = Random.new(424242)
    loc = Time::Location.load("Europe/Berlin")

    # PREDECLARE so rescue can see them
    base = Time.local(2023, 3, 26, 1, 0, 0, location: loc)
    step = 1.minute
    delta = 1.minute

    max_shift = 6.minutes
    max_shifts = 10

    begin
      year = 2023

      200.times do
        month = rng.rand(1..12)
        max_day = Time.days_in_month(year, month)
        day = rng.rand(1..max_day)

        hour = rng.rand(0..23)
        minute = rng.rand(0..59)

        anchor = Time.local(year, month, day, 0, 0, 0, location: loc)
        base = anchor + hour.hours + minute.minutes

        step = rng.rand(1..3).minutes
        delta = rng.rand(-6..6).minutes
        target = base + delta

        reachable = VirtualTime::Search.shifted_from_base?(target, step, max_shift: max_shift, max_shifts: max_shifts) do |candidate|
          candidate == base ? delta : nil
        end

        if reachable && delta.abs > max_shift
          raise "Invariant violation"
        end
      end
    rescue
      shrunk =
        shrink_case(base, step, delta, max_shift, max_shifts) do |shr_base, shr_step, shr_delta|
          shr_target = shr_base + shr_delta

          VirtualTime::Search.shifted_from_base?(shr_target, shr_step, max_shift: max_shift, max_shifts: max_shifts) { |candidate| candidate == shr_base ? shr_delta : nil } && shr_delta.abs > max_shift
        end

      message = "Search invariant failed. Shrunk failing case: base: #{shrunk[0]} step: #{shrunk[1]} delta: #{shrunk[2]} max_shift: #{max_shift}"
      fail message
    end
  end

  describe "DST-heavy Search fuzzer" do
    it "never violates soundness across DST transitions" do
      rng = Random.new(20240326)

      zones = [
        "Europe/Berlin",
        "America/New_York",
        "America/Sao_Paulo",
        "Australia/Sydney",
      ].map { |zone| Time::Location.load(zone) }

      year = 2023

      300.times do
        loc = zones.sample(rng)

        # Bias toward common DST-change months, but keep variety.
        month =
          case rng.rand(0..9)
          when 0, 1, 2, 3
            3 # March
          when 4, 5, 6, 7
            10 # October
          else
            rng.rand(1..12)
          end

        max_day = Time.days_in_month(year, month)
        day = rng.rand(1..max_day)

        hour = rng.rand(0..23)
        minute = rng.rand(0..59)

        # Midnight always exists; date is valid by construction.
        anchor = Time.local(year, month, day, 0, 0, 0, location: loc)

        # Move within the day using span arithmetic (DST-safe)
        base = anchor + hour.hours + minute.minutes

        step_minutes = rng.rand(-3..3)
        next if step_minutes == 0
        step = step_minutes.minutes

        delta_minutes = rng.rand(-6..6)
        delta = delta_minutes.minutes
        target = base + delta

        max_shift = 6.minutes
        max_shifts = 10

        reachable = VirtualTime::Search.shifted_from_base?(target, step, max_shift: max_shift, max_shifts: max_shifts) do |candidate|
          candidate == base ? delta : nil
        end

        # Soundness invariant only
        if reachable
          delta.abs.should be <= max_shift
          (base + delta).should eq(target)
        end
      end
    end

    it "handles month-end dates safely (calendar fuzz)" do
      rng = Random.new(20240327)
      loc = Time::Location.load("Europe/Berlin")

      100.times do
        month = rng.rand(1..12)
        max_day = Time.days_in_month(2023, month)
        day = rng.rand(1..max_day)

        anchor = Time.local(2023, month, day, 0, 0, 0, location: loc)
        anchor.should be_a(Time) # just sanity
      end
    end
  end
end
