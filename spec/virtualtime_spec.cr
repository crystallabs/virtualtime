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

  it "keeps the iterator advancing and both sides of a DST fall-back" do
    berlin = Time::Location.load("Europe/Berlin")
    new_york = Time::Location.load("America/New_York")

    # Regression: an ambiguous wall clock let `#to_time` answer with an instant
    # *before* the hint, and `#step` then repeated it for ever
    vt = VirtualTime.new hour: 1, minute: 30..59, second: 0..59, nanosecond: 0..999_999_999, location: new_york
    ambiguous = Time.utc(2022, 11, 6, 6, 30, 0).in(new_york) # 01:30 -05:00, the second of two
    vt.to_time(ambiguous).should eq ambiguous
    vt.succ(ambiguous).should be > ambiguous

    # A rule whose only match is in the past cannot produce a successor, and an
    # iterator must end rather than hand back the same value for ever
    past = VirtualTime.new year: 2000, month: 1, day: 1, hour: 0, minute: 0, second: 0, nanosecond: 0
    expect_raises(ArgumentError, /no match after/) do
      past.succ(Time.local(2024, 1, 1, location: berlin))
    end

    # Every minute of a whole year is generated exactly once, DST and all
    vt = VirtualTime.new minute: 30, second: 0, nanosecond: 0, location: berlin
    from = Time.local(2024, 1, 1, location: berlin)
    to = Time.local(2025, 1, 1, location: berlin)

    generated = [] of Time
    iterator = vt.step(1.minute, 1, from - 1.nanosecond)
    loop do
      value = iterator.next
      break unless value.is_a?(Time)
      break if value >= to
      generated << value
    end

    expected = [] of Time
    time = from
    while time < to
      expected << time if vt.matches? time
      time += 1.minute
    end

    generated.should eq expected
  end

  it "produces both sides of a DST fall-back whatever the rule looks like" do
    # Regression: the repeat was recovered by trying the single candidate one
    # fold earlier, which only lands right when the next materialized match
    # happens to be exactly a fold later
    berlin = Time::Location.load("Europe/Berlin")
    vt = VirtualTime.new hour: 2, minute: 30, second: 0, nanosecond: 0, location: berlin
    first = Time.utc(2023, 10, 29, 0, 30, 0).in(berlin)  # 02:30 +02:00
    second = Time.utc(2023, 10, 29, 1, 30, 0).in(berlin) # 02:30 +01:00

    vt.matches?(first).should be_true
    vt.matches?(second).should be_true
    vt.succ(first).should eq second

    # And the fold step is read off the zone rather than assumed to be an hour
    lord_howe = Time::Location.load("Australia/Lord_Howe")
    half = VirtualTime.new minute: 30, second: 0, nanosecond: 0, location: lord_howe
    from = Time.local(2023, 4, 2, 0, 0, 0, location: lord_howe)

    generated = [] of Time
    iterator = half.step(1.minute, 1, from - 1.nanosecond)
    loop do
      value = iterator.next
      break unless value.is_a?(Time)
      break if value >= from + 1.day
      generated << value
    end

    expected = [] of Time
    time = from
    while time < from + 1.day
      expected << time if half.matches? time
      time += 1.minute
    end

    generated.should eq expected
  end

  it "keeps the day walk on the day it asked for across a DST gap" do
    # Regression: the walk moves whole days and keeps the time of day, and a
    # wall clock a spring-forward swallowed came back as a neighbouring one --
    # in Santiago's case on the day before. The date that answered was then
    # rejected, the retry inherited the mangled time of day as its floor, and
    # a whole matching day was stepped over
    berlin = Time::Location.load "Europe/Berlin"
    vt = VirtualTime.new day_of_week: [7, 1], hour: 2, minute: 39, second: 0, nanosecond: 0
    vt.location = berlin

    # 2020-03-29 02:39 does not exist in Berlin; Monday the 30th does
    expected = Time.local(2020, 3, 30, 2, 39, 0, location: berlin)
    vt.matches?(expected).should be_true
    vt.to_time(Time.local(2020, 3, 26, 0, 0, 0, location: berlin)).should eq expected

    # Santiago's gap is at midnight, so the walk resolved backwards over the
    # date boundary and abandoned the target day outright
    santiago = Time::Location.load "America/Santiago"
    sunday = VirtualTime.new day_of_week: 7, second: 0, nanosecond: 0
    sunday.location = santiago

    first = Time.local(2027, 9, 5, 1, 0, 0, location: santiago)
    sunday.matches?(first).should be_true
    sunday.to_time(Time.local(2027, 9, 2, 0, 0, 0, location: santiago)).should eq first
    sunday.succ(Time.local(2027, 9, 1, 23, 59, 0, location: santiago)).should eq first

    # And a gap on the day materialization landed on must not follow it onto
    # the next one, where the wall clock it displaced exists again
    monday = VirtualTime.new day_of_week: 1, second: 0, nanosecond: 0
    monday.location = santiago
    monday.succ(Time.local(2018, 8, 11, 23, 59, 0, location: santiago))
      .should eq Time.local(2018, 8, 13, 0, 0, 0, location: santiago)
  end

  it "resolves a negative week against the ISO year it lands in, in a list too" do
    # Regression: `#anchor_to_iso_week` re-resolved the week per candidate year
    # but went on asking from the *original* week number. A negative week is 52
    # in one year and 53 in the next, so the stale number was itself allowed in
    # the following year -- and answered instead of that year's earliest week
    vt = VirtualTime.new week: [32, -2], hour: 0, minute: 0, second: 0, nanosecond: 0

    expected = Time.utc(2020, 8, 3)
    vt.matches?(expected).should be_true
    vt.succ(Time.utc(2019, 12, 22)).should eq expected
  end

  it "resolves a negative day of year against the year it lands in" do
    # Regression: the wrap into the following year sized the wanted day by the
    # year being left behind, which is a day out whenever a leap year is
    # crossed -- so every year after a leap year was skipped
    vt = VirtualTime.new day_of_year: -4, hour: 0, minute: 0, second: 0, nanosecond: 0

    expected = Time.utc(2021, 12, 28)
    vt.matches?(expected).should be_true
    vt.succ(Time.utc(2020, 12, 28)).should eq expected
  end

  it "restarts the time of day when the date walk moves the date" do
    # Regression: `#materialize_with_hint` rewinds the finer fields when a
    # coarser one advances, but the week / day-of-week / day-of-year walks run
    # afterwards and moved the date without re-asking for the time of day. The
    # hour was picked while the date was still the hint's own
    vt = VirtualTime.new
    vt.year = 2021
    vt.month = 5
    vt.day = 1..31
    vt.week = 1..53
    vt.day_of_week = 4
    vt.day_of_year = 1..366
    vt.hour = [3, 9]
    vt.minute = 11
    vt.second = 0
    vt.millisecond = 0
    vt.nanosecond = 0

    expected = Time.utc(2021, 5, 6, 3, 11)
    vt.matches?(expected).should be_true
    vt.to_time(Time.utc(2021, 5, 1, 8, 40)).should eq expected

    # Where the restarted time of day is missing from the date -- a DST gap --
    # the date still keeps whatever it matches later on
    santiago = Time::Location.load "America/Santiago"
    gapped = VirtualTime.new day_of_week: 7, hour: [0, 16], minute: 12, second: 0, nanosecond: 0
    gapped.location = santiago

    # Sunday 2021-09-05 has no 00:12 in Santiago, but it does have 16:12
    later = Time.local(2021, 9, 5, 16, 12, 0, location: santiago)
    gapped.matches?(later).should be_true
    gapped.to_time(Time.local(2021, 9, 3, 13, 13, 0, location: santiago)).should eq later
  end

  it "keeps matching commutative when the two sides disagree on default_match" do
    # Regression: an unconstrained field was judged by the *receiver's*
    # `#default_match?` whichever side it came from, so which of the two was
    # asked decided the answer -- against the README's own claim
    a = VirtualTime.new hour: 5, default_match: false
    b = VirtualTime.new month: 3

    a.matches?(b).should eq b.matches?(a)
    a.matches?(b).should be_false

    # An unconstrained field on a permissive side still lets a constrained one
    # on the other through, whichever way round it is asked
    c = VirtualTime.new hour: 5
    d = VirtualTime.new month: 3
    c.matches?(d).should be_true
    d.matches?(c).should be_true
  end

  it "reports that nothing matches rather than wrapping past the calendar" do
    # Regression: the year carried past 9999 wrapped modularly like the cyclic
    # fields below it, answering a question about year 10000 with year 1
    expect_raises ArgumentError, /within the calendar/ do
      VirtualTime.new(month: 1, day: 1).to_time Time.utc(9999, 6, 1)
    end

    # A `#year` naming a bygone year is a different matter and still answers
    VirtualTime.new(year: 2000, month: 1, day: 1, hour: 0, minute: 0, second: 0, nanosecond: 0)
      .to_time(Time.utc(2024, 6, 1)).should eq Time.utc(2000, 1, 1)
  end

  it "keeps a date whose earliest allowed time of day a DST gap swallowed" do
    # Regression: when the walk landed on a gap it stood on the gap's end,
    # whose time of day the rule does not ask for. Restarting the time of day
    # then refused to look again -- there was nothing earlier to find -- and
    # the whole date was abandoned, along with every match it still had
    zagreb = Time::Location.load "Europe/Zagreb"
    vt = VirtualTime.new day_of_week: 7, hour: 2..23, minute: 5, second: 0, nanosecond: 0

    # 2018-03-25 has no 02:05 in Zagreb; 03:05 is the day's first match
    expected = Time.local(2018, 3, 25, 3, 5, 0, location: zagreb)
    vt.matches?(expected).should be_true
    vt.to_time(Time.local(2018, 3, 22, 0, 0, 0, location: zagreb)).should eq expected

    # A hint carrying a time of day the gap does not hold answered correctly
    # already, and still does
    vt.to_time(Time.local(2018, 3, 22, 4, 0, 0, location: zagreb)).should eq expected

    # ... and with every date field constrained too, so hint filling has no say
    ny = Time::Location.load "America/New_York"
    fixed = VirtualTime.new day: 1..27, day_of_week: 7, hour: 2..18, minute: 45,
      second: 0, nanosecond: 0

    sunday = Time.local(2022, 3, 13, 3, 45, 0, location: ny)
    fixed.matches?(sunday).should be_true
    fixed.to_time(Time.local(2022, 3, 7, 2, 45, 0, location: ny)).should eq sunday
  end

  it "keeps two unconstrained fields commutative across default_match" do
    # Regression: a nil against a nil answered with one side's `#default_match?`
    # alone, and every field is nil by default -- so nearly every comparison
    # between two `VirtualTime`s that disagreed on it depended on which was
    # asked
    a = VirtualTime.new hour: 5
    b = VirtualTime.new hour: 5, default_match: false

    a.matches?(b).should eq b.matches?(a)
    a.matches?(b).should be_false

    vt = VirtualTime.new
    vt.matches?(nil, nil, 24, a_default: true, b_default: false)
      .should eq vt.matches?(nil, nil, 24, a_default: false, b_default: true)

    # Two permissive sides still meet
    VirtualTime.new(hour: 5).matches?(VirtualTime.new(hour: 5)).should be_true
  end

  it "compares and hashes two identical stepped ranges as one rule" do
    # Regression: a stepped range is a `Steppable::StepIterator`, a reference
    # type with no equality of its own, so two rules written from the same
    # literal fell back to identity -- and took two slots in a `Set` that
    # `#hash`'s own doc says is meant to dedupe them
    a = VirtualTime.new
    a.hour = (10..20).step(2)
    b = VirtualTime.new
    b.hour = (10..20).step(2)

    a.should eq b
    a.hash.should eq b.hash
    Set{a, b}.size.should eq 1
    VirtualTime.from_yaml(a.to_yaml).should eq a

    # A different step is still a different rule
    c = VirtualTime.new
    c.hour = (10..20).step(3)
    c.should_not eq a
  end

  it "restarts the date when a coarser field moves past the hint" do
    # Regression: the week / day-of-week / day-of-year walk starts from the
    # month and day materialization took from the *hint*, carried into a year
    # the `#year` rule moved on to. The walk only goes forward, so a target
    # earlier in that year was stepped over -- and where the year was pinned,
    # the wrap out of it left the rule looking unsatisfiable
    pinned = VirtualTime.new year: 2032, week: 20
    hint = Time.utc 2031, 8, 12, 8, 17, 37

    expected = Time.utc 2032, 5, 10, 8, 17, 37
    pinned.matches?(expected).should be_true
    pinned.to_time(hint).should eq expected
    # Dropping only the year already answered with that instant
    VirtualTime.new(week: 20).to_time(hint).should eq expected

    VirtualTime.new(year: 2027..2029, day_of_year: 26).to_time(Time.utc(2026, 5, 2, 6, 40, 54))
      .should eq Time.utc(2027, 1, 26, 6, 40, 54)

    # ... and with the time of day fully constrained, so hint filling has no say
    listed = VirtualTime.new year: 2022, day_of_year: [164, 183], hour: 11, minute: 52, second: 26
    listed.nanosecond = 0
    listed.to_time(Time.utc(2021, 8, 21, 22, 4, 46)).should eq Time.utc(2022, 6, 13, 11, 52, 26)
  end

  it "leaves a proc-valued field alone when finer fields restart" do
    # Regression: the restart puts every constrained finer field back at the
    # bottom of its range and trusts materialization to bring it up again --
    # which it cannot do for a proc, so the field stayed at zero and a rule the
    # proc plainly accepts became unsatisfiable
    vt = VirtualTime.new minute: 0, second: 0, day: 20
    vt.hour = VirtualTime::VirtualProc.new { |hour| hour >= 15 }
    hint = Time.utc 2021, 1, 6, 15, 0, 0

    expected = Time.utc 2021, 1, 20, 15, 0, 0
    vt.matches?(expected).should be_true
    vt.materialize_with_hint(hint)[:hour].should eq 15
    vt.to_time(hint).should eq expected

    # The same rule with a date walk rather than a `#day` rule
    walked = VirtualTime.new minute: 0, second: 0, day_of_week: 3
    walked.hour = VirtualTime::VirtualProc.new { |hour| hour >= 15 }
    walked.to_time(hint).should eq Time.utc(2021, 1, 6, 15, 0, 0)
  end

  it "sizes a negative day by the month the restart reached" do
    # Regression: the restart hands the pass January, a negative `#day` was
    # sized by that rather than by the month the pass arrived at, and the
    # refined spec then read as *later* than the first pass -- so the whole
    # restart was discarded, hour and all
    vt = VirtualTime.new month: 4, day: -2, hour: 15..21, minute: 0, second: 0

    expected = Time.utc 2027, 4, 29, 15, 0, 0
    vt.matches?(expected).should be_true
    vt.to_time(Time.utc(2026, 9, 28, 17, 0, 0)).should eq expected
  end

  it "keeps the hint's own day under strict: false" do
    # Regression: materialization asked the day to satisfy the rule even when
    # it was deliberately the hint's own, so every candidate was refused and
    # the month hops ran out before `#to_time` had anything to walk from
    hint = Time.utc 2021, 1, 5, 20, 45, 13

    VirtualTime.new(day: 15).to_time(hint, false).should eq Time.utc(2021, 1, 15, 20, 45, 13)
    # The shapes that already worked still do
    VirtualTime.new(hour: 10..12).to_time(hint, false).should eq hint
    # An unconstrained day keeps the hint's own, as it does under `strict: true`
    VirtualTime.new(month: 3).to_time(hint, false).should eq Time.utc(2021, 3, 5, 20, 45, 13)
    VirtualTime.new(month: 3).to_time(hint, true).should eq Time.utc(2021, 3, 5, 20, 45, 13)

    # A date the rule can only reach months away is named outright rather than
    # crawled towards a day at a time, which used to run out of attempts
    VirtualTime.new(month: 3, day: 1).to_time(Time.utc(2019, 10, 31, 20, 44, 51), false)
      .should eq Time.utc(2020, 3, 1, 20, 44, 51)
    # ... and a time of day the wanted date cannot hold has no say over it
    zagreb = Time::Location.load "Europe/Zagreb"
    gapped = VirtualTime.new day: -1, hour: 2
    gapped.to_time(Time.local(2024, 3, 23, 17, 20, 25, location: zagreb), false)
      .should eq Time.local(2024, 3, 31, 17, 20, 25, location: zagreb)
  end

  it "reads a stepped range as its whole run, however far it has been consumed" do
    # Regression: a stored iterator was duplicated rather than rebuilt, so one
    # that a caller had read a value from went on describing a shorter rule --
    # while still comparing and hashing equal to an untouched one
    a = VirtualTime.new
    a.hour = (0..23).step(6)
    b = VirtualTime.new
    b.hour = (0..23).step(6)
    b.hour.as(Steppable::StepIterator(Int32, Int32, Int32)).next

    a.should eq b
    midnight = Time.utc 2021, 1, 1, 0, 30, 0
    a.matches?(midnight).should be_true
    b.matches?(midnight).should eq a.matches?(midnight)

    # A list is the same rule whichever container holds it and in whatever
    # order it is written -- which is what a YAML round trip relies on
    listed = VirtualTime.new
    listed.hour = Set{17, 10}
    VirtualTime.from_yaml(listed.to_yaml).should eq listed
  end

  it "agrees with #matches? that a stepped range yielding nothing is unusable" do
    # Regression: `#matches?` let nothing through for a step of zero while
    # materialization expanded it to a value, and said so only after burning
    # every attempt it had
    vt = VirtualTime.new minute: 0, second: 0, nanosecond: 0
    vt.hour = (2..2).step(0)

    vt.matches?(Time.utc(2021, 1, 1, 2, 0, 0)).should be_false
    expect_raises ArgumentError, /yields nothing/ do
      vt.to_time Time.utc(2021, 1, 1)
    end
  end

  it "tests a large stepped range by arithmetic rather than by walking it" do
    # The code beside it says iterating a range of nanoseconds "is
    # catastrophic"; the stepped form used to do exactly that, taking a third
    # of a second per comparison and a gigabyte to materialize
    vt = VirtualTime.new hour: 12, minute: 30, second: 0
    vt.nanosecond = (0..999_999_999).step(3)

    vt.matches?(Time.utc(2021, 1, 1, 12, 30, 0, nanosecond: 999_999_999)).should be_true
    vt.matches?(Time.utc(2021, 1, 1, 12, 30, 0, nanosecond: 999_999_998)).should be_false

    answered = vt.to_time Time.utc(2021, 1, 1, 12, 30, 0, nanosecond: 1)
    answered.nanosecond.should eq 3
    vt.matches?(answered).should be_true
  end

  it "sizes a negative day by the month it materializes into" do
    # Regression: the first pass sizes `day: -1` by the *hint's* month, and the
    # restart that re-sizes it against the month reached was only ever taken
    # when it named an *earlier* day. Correcting 30 to 31 names a later one, so
    # it was thrown away and `#materialize` answered with a day its own rule
    # does not allow
    vt = VirtualTime.new
    vt.month = 12
    vt.day = -1
    hint = Time.utc 2025, 9, 5

    vt.materialize(hint).day.should eq 31
    vt.to_time(hint).should eq Time.utc(2025, 12, 31)
    vt.matches?(Time.utc(2025, 12, 31)).should be_true
  end

  it "puts an unconstrained finer field back to the hint's own value" do
    # Regression: a carry raised to keep the answer at or after the hint stayed
    # on an unconstrained field after a coarser one had moved past the hint and
    # settled that question by itself -- so the answer was a minute, a day or a
    # month later than the hint asked for, and `#succ` skipped a real match
    VirtualTime.new(hour: 9, second: 0).to_time(Time.utc(2024, 1, 1, 8, 0, 30))
      .should eq Time.utc(2024, 1, 1, 9, 0, 0)

    # Constraining the same field to its whole domain already answered this way
    whole = VirtualTime.new hour: 9, second: 0
    whole.minute = 0..59
    whole.to_time(Time.utc(2024, 1, 1, 8, 0, 30)).should eq Time.utc(2024, 1, 1, 9, 0, 0)

    VirtualTime.new(month: 3, hour: 0).to_time(Time.utc(2024, 1, 5, 12)).should eq Time.utc(2024, 3, 5)
    VirtualTime.new(year: 2026, hour: 0).to_time(Time.utc(2024, 6, 15, 12)).should eq Time.utc(2026, 6, 15)

    VirtualTime.new(hour: 9, second: 0, nanosecond: 0).succ(Time.utc(2024, 1, 1, 8, 0, 0))
      .should eq Time.utc(2024, 1, 1, 9, 0, 0)
  end

  it "never lets a restart move a field forward" do
    # Regression: an unconstrained field went back to the hint's value, but
    # where materialization reached its own value by *wrapping* -- December
    # into January, the 31st into the 1st -- the hint's value is the larger of
    # the two. The restart then named a date a year off, was thrown away for
    # reading as later than the pass it refined, and took the constrained
    # minute's reset with it
    vt = VirtualTime.new day: 18, hour: 16, minute: [14, 51], second: 0
    vt.nanosecond = 0
    vt.to_time(Time.utc(2023, 12, 29, 0, 30, 0)).should eq Time.utc(2024, 1, 18, 16, 14)

    day_wrap = VirtualTime.new hour: 3, minute: [14, 51], second: 0
    day_wrap.nanosecond = 0
    day_wrap.to_time(Time.utc(2024, 1, 31, 20, 30, 0)).should eq Time.utc(2024, 2, 1, 3, 14)
  end

  it "does not carry a spent carry through the date walk" do
    # Regression: the clock an unconstrained field restarts at came from
    # materialization, which had raised a carry to keep the answer at or after
    # the hint. Once the walk moved onto a later date that carry was spent, but
    # the hour restarted at the carried value all the same
    {
      {VirtualTime.new(day_of_week: 3, minute: 43, second: 0), Time.utc(2022, 7, 6, 8, 43)},
      {VirtualTime.new(week: 30, minute: 43, second: 0), Time.utc(2022, 7, 25, 8, 43)},
      {VirtualTime.new(day_of_year: 200, minute: 43, second: 0), Time.utc(2022, 7, 19, 8, 43)},
    }.each do |(vt, expected)|
      vt.nanosecond = 0
      vt.matches?(expected).should be_true
      vt.to_time(Time.utc(2022, 7, 5, 8, 54, 0)).should eq expected
    end
  end

  it "restarts on a clock a DST gap swallowed" do
    # Regression: the restart hint was built in the search's own zone, so a
    # wall clock a spring-forward swallowed came back as a neighbouring one --
    # and which side of the gap that is, is the zone's own business. It is read
    # for its fields and never as an instant, so the zone has no business in it
    sydney = Time::Location.load "Australia/Sydney"
    vt = VirtualTime.new month: 10, day: [14, 20], minute: [30, 45]

    expected = Time.local 2023, 10, 14, 2, 30, 9, location: sydney
    vt.matches?(expected).should be_true
    vt.to_time(Time.local(2023, 1, 21, 2, 35, 9, location: sydney)).should eq expected
  end

  it "answers loosely wherever it answers strictly" do
    # Regression: a rule the strict mode answers cannot become unsatisfiable by
    # relaxing it, and a bygone-year answer is not made unacceptable by being
    # before the hint -- refusing it only sent the search crawling forward
    bygone = VirtualTime.new year: 2020, day_of_year: 310
    bygone.to_time(Time.utc(2021, 4, 27), false).should eq bygone.to_time(Time.utc(2021, 4, 27), true)

    plain = VirtualTime.new year: 2020
    hint = Time.utc 2023, 3, 15, 17, 49, 0
    plain.to_time(hint, false).should eq Time.utc(2020, 3, 15, 17, 49)
    plain.to_time(hint, true).should eq plain.to_time(hint, false)
  end

  it "walks to a proc-valued day instead of hopping months past it" do
    # Regression: materialization hands a proc the wanted value back, so
    # insisting the day satisfy one left the search hopping months that all
    # offer the same first day, and it gave up on a rule it plainly matches
    vt = VirtualTime.new minute: 25, second: 0
    vt.day = ->(day : Int32) { day == 21 }
    vt.nanosecond = 0

    expected = Time.utc 2023, 12, 21, 5, 25
    vt.matches?(expected).should be_true
    vt.to_time(Time.utc(2023, 12, 12, 5, 31, 0)).should eq expected
  end

  it "settles a millisecond rule against a nanosecond one" do
    # Regression: both name the same field of a `Time`, and folding the
    # millisecond in named a nanosecond the nanosecond rule rejects -- so the
    # answer satisfied neither and the search lost a whole day
    vt = VirtualTime.new
    vt.millisecond = 71..503
    vt.nanosecond = [565_000_000, 238_000_000]

    expected = Time.utc 2023, 6, 15, 11, 59, 58, nanosecond: 238_000_000
    vt.matches?(expected).should be_true
    vt.succ(Time.utc(2023, 6, 15, 11, 59, 57, nanosecond: 300_000_000)).should eq expected
  end

  it "re-sizes a negative day against a pinned month it has already gone by" do
    # Regression: the retry that re-sizes a day by the month the pass reached
    # only moved *forward*, so a `#year` and `#month` both pinned to a month
    # already past left it landing on the same spec every time until its
    # attempts ran out
    vt = VirtualTime.new
    vt.year = 2001
    vt.month = 1
    vt.day = -1

    vt.matches?(Time.utc(2001, 1, 31)).should be_true
    vt.to_time(Time.utc(2001, 2, 1)).should eq Time.utc(2001, 1, 31)

    # ... and `#materialize` sized the day by the hint's own month, which for a
    # bygone year is not one the restart pass ever notices
    backwards = VirtualTime.new
    backwards.year = 2001
    backwards.month = -1
    backwards.day = -2
    materialized = backwards.materialize Time.utc(2002, 6, 27, 23, 3, 26)
    materialized.day.should eq 30
    # The hint still fills the fields nothing constrains
    materialized.hour.should eq 23
  end

  it "walks a pinned year again from its start when the walk runs off the end" do
    # Regression: a `#year` that cannot move has no room for a walk that left
    # it -- the walk went forward into the next year, the year rule pulled the
    # date back, and the search alternated between the two until it gave up
    doy = VirtualTime.new
    doy.year = 2004
    doy.day_of_year = 107
    doy.to_time(Time.utc(2004, 12, 31)).should eq Time.utc(2004, 4, 16)
    doy.to_time(Time.utc(2004, 1, 1)).should eq Time.utc(2004, 4, 16)

    week = VirtualTime.new
    week.year = 2004
    week.week = 20
    answered = week.to_time Time.utc(2004, 12, 31)
    week.matches?(answered).should be_true
    answered.year.should eq 2004
  end

  it "walks to a proc-valued time of day by the unit it measures" do
    # Regression: the retry only ever moved the date on, so an hour a proc
    # decides was met with the same clock a hundred times over and the search
    # gave up on a rule it plainly matches
    vt = VirtualTime.new
    vt.hour = ->(hour : Int32) { hour == 18 }

    expected = Time.utc 2001, 1, 1, 18
    vt.matches?(expected).should be_true
    vt.to_time(Time.utc(2001, 1, 1)).should eq expected

    by_minute = VirtualTime.new hour: 5
    by_minute.minute = ->(minute : Int32) { minute == 43 }
    by_minute.to_time(Time.utc(2001, 1, 1)).should eq Time.utc(2001, 1, 1, 5, 43)
  end

  it "finds the end of a gap wider than a day" do
    # Regression: the search for the instant a gap ends reached two hours
    # either side, and Samoa skipped a whole day crossing the date line -- so
    # `#succ` stepped over the first match on the far side of it
    apia = Time::Location.load "Pacific/Apia"
    vt = VirtualTime.new
    vt.minute = [0, 15, 30, 45]

    expected = Time.local 2011, 12, 31, 0, 0, 0, location: apia
    vt.matches?(expected).should be_true
    vt.succ(Time.local(2011, 12, 29, 23, 45, 59, nanosecond: 999_999_999, location: apia))
      .should eq expected
  end

  it "moves on to a later month without carrying the hint's clock into it" do
    # Regression: the retry that moves on when a day did not fit carried the
    # hint's own clock into the month it moved to -- flooring every constrained
    # time-of-day field at a clock that month was never about, and letting the
    # carry that followed re-select the day. A whole month of matches was
    # stepped over, and with a pinned month the search oscillated between two
    # of them until its attempts ran out
    vt = VirtualTime.new
    vt.day = [1, 31]
    vt.hour = 2
    vt.minute = 0
    vt.second = 0
    vt.nanosecond = 0
    vt.to_time(Time.utc(2018, 9, 29, 3, 0, 0)).should eq Time.utc(2018, 10, 1, 2)

    # The constrained hour restarts at its minimum in the month reached
    st_johns = Time::Location.load "America/St_Johns"
    ranged = VirtualTime.new
    ranged.year = 2025
    ranged.month = 1..12
    ranged.day = [1, 31]
    ranged.hour = 8..17
    ranged.minute = 59
    ranged.second = 0
    ranged.nanosecond = 0
    ranged.to_time(Time.local(2025, 6, 24, 11, 17, 21, location: st_johns))
      .should eq Time.local(2025, 7, 1, 8, 59, 0, location: st_johns)

    pinned = VirtualTime.new
    pinned.year = 2030
    pinned.month = 2
    pinned.day = [1, 31]
    pinned.hour = 5
    pinned.minute = 0
    pinned.second = 0
    pinned.nanosecond = 0
    pinned.matches?(Time.utc(2030, 2, 1, 5)).should be_true
    pinned.to_time(Time.utc(2030, 2, 15, 23)).should eq Time.utc(2030, 2, 1, 5)
  end

  it "re-sizes a day into a later month without carrying the hint's clock" do
    # Regression: re-sizing a day against the month a pass reached carried the
    # hint's own clock into it. Where that month is a *later* one, the clock
    # has nothing to say about it -- and flooring a constrained hour at it
    # raised a carry off the day, skipping the month entirely or answering
    # before the hint
    vt = VirtualTime.new
    vt.month = 2
    vt.day = -28
    vt.hour = 0
    vt.minute = 0
    vt.second = 0
    vt.millisecond = 0
    vt.nanosecond = 0

    # `day: -28` is the 1st of a 28-day February
    vt.matches?(Time.utc(2025, 2, 1)).should be_true
    vt.to_time(Time.utc(2024, 2, 29, 12)).should eq Time.utc(2025, 2, 1)

    # ... and an allowed later year is not passed over for a bygone one
    ranged = VirtualTime.new
    ranged.year = [2024, 2025]
    ranged.month = 1
    ranged.day = -31
    ranged.hour = 0
    ranged.minute = 0
    ranged.second = 0
    ranged.millisecond = 0
    ranged.nanosecond = 0
    ranged.to_time(Time.utc(2024, 2, 29, 12)).should eq Time.utc(2025, 1, 1)
  end

  it "resolves a negative day against its month only once" do
    # Regression: `#materialize` resolved negatives a second time on top of
    # `#adjust_value`, which is not idempotent -- a `-31` sized by a 29-day
    # February came back as `-2`, and a second pass turned that into 27, a day
    # the rule never named
    ranged = VirtualTime.new
    ranged.month = 2
    ranged.day = -31..-28
    ranged.hour = 12
    ranged.minute = 30
    ranged.second = 0
    ranged.millisecond = 0
    ranged.nanosecond = 0

    ranged.matches?(Time.utc(2024, 2, 1, 12, 30)).should be_true
    ranged.to_time(Time.utc(2024, 1, 1)).should eq Time.utc(2024, 2, 1, 12, 30)

    # The same in a list, where a member too large for the month is simply not
    # one the month offers
    listed = VirtualTime.new
    listed.year = 2025
    listed.month = 2
    listed.day = [-1, -31]
    listed.hour = 0
    listed.minute = 0
    listed.second = 0
    listed.millisecond = 0
    listed.nanosecond = 0

    listed.matches?(Time.utc(2025, 2, 28)).should be_true
    listed.to_time(Time.utc(2025, 1, 1)).should eq Time.utc(2025, 2, 28)
  end

  it "materializes a proc-valued field by asking it" do
    # Regression: a `Proc` was left at whatever the hint supplied, so the
    # search had to stumble onto a match by walking -- which cannot reach a
    # time of day at all. Asking the proc which values it allows gives the same
    # answer the equivalent list does
    vt = VirtualTime.new
    vt.hour = 21
    vt.minute = VirtualTime::VirtualProc.new { |value| value % 4 == 0 }

    expected = Time.utc 2025, 5, 2, 21
    vt.matches?(expected).should be_true
    vt.to_time(Time.utc(2025, 5, 2, 0, 57, 0)).should eq expected

    listed = VirtualTime.new
    listed.hour = 21
    listed.minute = (0..59).select { |value| value % 4 == 0 }
    vt.to_time(Time.utc(2025, 5, 2, 0, 57, 0)).should eq listed.to_time(Time.utc(2025, 5, 2, 0, 57, 0))

    # ... and it restarts at its own earliest allowed value like any other
    # constrained field once a coarser one moves on. The unconstrained second
    # and nanosecond still come from the hint, so the list is what it is held
    # against rather than a literal
    from = Time.utc 2025, 4, 24, 12, 49, 0
    vt.succ(from).should eq listed.succ(from)
    vt.succ(from).minute.should eq 0

    # A nanosecond is the one field too wide to ask about value by value, and
    # still keeps whatever it was given
    wide = VirtualTime.new hour: 5, minute: 0, second: 0
    wide.nanosecond = VirtualTime::VirtualProc.new(&.zero?)
    wide.matches?(Time.utc(2025, 1, 1, 5)).should be_true
  end

  it "starts the walk again in a later allowed year rather than answering behind the hint" do
    # Regression: restarting a pinned year at January let the walk find a match
    # earlier in that year and settle for it, without ever checking the answer
    # was still at or after the hint. `#succ` then raised and `#step`
    # truncated. An answer in the past is right only where the rule has no year
    # left at or after the hint
    vt = VirtualTime.new
    vt.year = [2024, 2026]
    vt.week = 52

    expected = Time.utc 2026, 12, 21
    vt.matches?(expected).should be_true
    vt.to_time(Time.utc(2024, 12, 30)).should eq expected

    # ... and a rule naming solely bygone years still answers in the past
    bygone = VirtualTime.new year: 2020
    hint = Time.utc 2023, 3, 15, 17, 49, 0
    bygone.to_time(hint).should eq Time.utc(2020, 3, 15, 17, 49)
  end

  it "keeps a year list from wrapping back to its earliest year" do
    # Regression: a refined spec naming a day its month cannot hold read as
    # "earlier" on the raw integers and was accepted, and the carries that
    # followed ran the year rule past its last allowed year and wrapped it to
    # its first -- twenty months before the hint
    vt = VirtualTime.new
    vt.year = [2024, 2026]
    vt.month = Set{2, 9}
    vt.day = -30
    vt.hour = 0

    expected = Time.utc 2026, 9, 1
    vt.matches?(expected).should be_true
    vt.to_time(Time.utc(2025, 5, 31, 6, 30, 0)).should eq expected
  end

  it "ignores a negative magnitude wider than the field beside a usable value" do
    # Regression: removing the second negative resolution left `#materialize`
    # picking a value no date has -- `-9` for a day of the week resolves to
    # `-1` -- and handing it to `Time`, which refuses it. `#matches?` lets
    # nothing through for such a value while still honouring the ones beside it
    hint = Time.utc 2024, 2, 29, 13, 45, 17

    weekly = VirtualTime.new
    weekly.day_of_week = [-9, 1]
    weekly.matches?(Time.utc(2024, 3, 4)).should be_true
    weekly.to_time(hint).should eq Time.utc(2024, 3, 4, 13, 45, 17)

    seconds = VirtualTime.new
    seconds.second = [-117, 0]
    seconds.to_time(hint).should eq Time.utc(2024, 2, 29, 13, 46)
  end

  it "carries a list value the hint's own month cannot hold on to one that can" do
    # Regression: filtering values outside a field's domain used the field's
    # `max`, which for a `#day` is the length of the *hint's* month -- so a 31
    # asked about from April was thrown out as nonsense rather than carried on
    # to a month that has one, and the list came back empty
    listed = VirtualTime.new
    listed.day = [31]

    expected = Time.utc 2024, 5, 31
    listed.matches?(expected).should be_true
    listed.to_time(Time.utc(2024, 4, 5)).should eq expected
    # Every other spelling of the same rule already answered this way
    listed.to_time(Time.utc(2024, 4, 5)).should eq VirtualTime.new(day: 31).to_time(Time.utc(2024, 4, 5))

    week = VirtualTime.new
    week.week = [53]
    week.to_time(Time.utc(2023, 1, 1)).should eq VirtualTime.new(week: 53).to_time(Time.utc(2023, 1, 1))

    # A magnitude below the field's own floor is still nonsense and still goes
    below = VirtualTime.new
    below.day_of_week = [-9, 1]
    below.to_time(Time.utc(2024, 2, 29, 13, 45, 17)).should eq Time.utc(2024, 3, 4, 13, 45, 17)
  end

  it "does not walk the clock when it is the date that has not been reached" do
    # Regression: the retry for a proc-valued time of day ran on every failed
    # iteration, so where `#matches_date?` was what failed the search advanced
    # a minute at a time and spent all its attempts inside two hours
    vt = VirtualTime.new
    vt.day = [15, 20]
    vt.day_of_week = 3
    vt.minute = ->(value : Int32) { value == 0 }

    expected = Time.utc 2026, 5, 20
    vt.matches?(expected).should be_true
    vt.to_time(Time.utc(2026, 4, 16)).should eq expected
  end

  it "restarts the constrained finer fields when a coarser one moves on" do
    # Every field here is constrained, so the documented "unconstrained fields
    # come from the hint" carve-out does not apply. Regression: each field was
    # fixed while the coarser ones still held the hint's values, and when a
    # coarser one then moved forward the finer choice was never revisited --
    # stepping over the earliest match
    {
      {VirtualTime.new(hour: 3..10, minute: [29, 54], second: 0, nanosecond: 0),
       Time.utc(2020, 1, 1, 2, 45, 0), Time.utc(2020, 1, 1, 3, 29, 0)},
      {VirtualTime.new(month: 6..9, day: [3, 25], hour: 0, minute: 0, second: 0, nanosecond: 0),
       Time.utc(2020, 2, 10), Time.utc(2020, 6, 3)},
      {VirtualTime.new(day: 10..20, hour: [5, 18], minute: 0, second: 0, nanosecond: 0),
       Time.utc(2020, 1, 5, 9, 0, 0), Time.utc(2020, 1, 10, 5, 0, 0)},
      {VirtualTime.new(minute: 30..50, second: [7, 40], nanosecond: 0),
       Time.utc(2020, 1, 1, 0, 10, 20), Time.utc(2020, 1, 1, 0, 30, 7)},
    }.each do |(vt, hint, expected)|
      vt.matches?(expected).should be_true
      vt.to_time(hint).should eq expected
    end

    # An unconstrained field still takes the hint's value, as documented
    vt = VirtualTime.new year: 2018, day: 15, hour: 0
    hint = Time.utc(2023, 12, 9, 12, 56, 26, nanosecond: 837441132)
    vt.materialize(hint).to_tuple.should eq({2018, 12, 15, nil, nil, nil, 0, 56, 26, nil, 837441132, nil})
  end

  it "anchors a week on the wanted day, not on the hint's own" do
    vt = VirtualTime.new week: 8, day_of_week: 1..3, hour: 12, minute: 0, second: 0, nanosecond: 0
    monday = Time.utc(2020, 2, 17, 12, 0, 0) # the Monday of ISO week 8

    vt.matches?(monday).should be_true

    # Regression: the day of week was snapped to the first allowed value at or
    # after the *hint's* day of week, so a Wednesday hint skipped to Wednesday
    # of the target week -- and a later hint gave an earlier answer
    vt.to_time(Time.utc(2020, 1, 1)).should eq monday # a Wednesday
    vt.to_time(Time.utc(2020, 1, 2)).should eq monday # a Thursday
  end

  it "resumes just past a DST gap rather than beyond the matches next to it" do
    lord_howe = Time::Location.load("Australia/Lord_Howe") # gap 02:00-02:29 on 2020-10-04
    vt = VirtualTime.new minute: [22, 37], second: 0, nanosecond: 0, location: lord_howe
    expected = Time.local(2020, 10, 4, 2, 37, 0, location: lord_howe)

    # Regression: the retry started from whichever side of the gap `Time.local`
    # resolved to and carried that side's time of day along, so 02:37 -- which
    # exists and matches -- was stepped over
    vt.matches?(expected).should be_true
    vt.to_time(Time.local(2020, 10, 4, 1, 38, 0, location: lord_howe)).should eq expected

    santiago = Time::Location.load("America/Santiago") # gap 00:00-00:59 on 2020-09-06
    vt = VirtualTime.new month: 9, day: 6, minute: 0, second: 0, nanosecond: 0, location: santiago
    vt.to_time(Time.local(2020, 9, 1, 0, 0, 0, location: santiago))
      .should eq Time.local(2020, 9, 6, 1, 0, 0, location: santiago)
  end

  it "settles rules whose week or day of year walk lands outside the month" do
    # Regression: the retry re-materialized the day from the date the walk had
    # reached, and the leftover day pushed the answer past every matching date
    # -- the same way again a year later, so no number of attempts would do
    vt = VirtualTime.new month: [2, 5], week: 16..19, second: 0, nanosecond: 0
    vt.matches?(Time.utc(2020, 5, 1)).should be_true
    vt.to_time(Time.utc(2020, 1, 1)).should eq Time.utc(2020, 5, 1)

    vt = VirtualTime.new month: [1, 10], day_of_year: 54..281, second: 0, nanosecond: 0
    vt.matches?(Time.utc(2020, 10, 1)).should be_true
    vt.to_time(Time.utc(2020, 1, 1)).should eq Time.utc(2020, 10, 1)
  end

  it "keeps the restarted finer fields when a coarser one has moved on" do
    # Regression: the restart was anchored on the *hint's* value for the field
    # that had moved, so the second pass undid the move, landed before the hint
    # and was thrown away -- restart and all
    vt = VirtualTime.new year: [2021, 2023], month: 5, day: 22,
      hour: 5..23, minute: [10, 39, 42], second: 0, nanosecond: 0
    vt.to_time(Time.utc(2021, 9, 1, 15, 30, 0)).should eq Time.utc(2023, 5, 22, 5, 10, 0)

    vt = VirtualTime.new year: 2022, month: [2, 5, 7, 10], day: 7,
      hour: (2..22).step(2), minute: 40, second: 0, nanosecond: 0
    vt.to_time(Time.utc(2022, 2, 28, 19, 46, 0)).should eq Time.utc(2022, 5, 7, 2, 40, 0)

    # The same failure compounded into an answer *before* the hint, and a
    # `#succ` that raised although a later match existed
    vt = VirtualTime.new year: 2022..2023, month: 1, day: [8, 16, 24],
      hour: 9, minute: 40, second: 0, nanosecond: 0
    vt.day_of_week = 7
    expected = Time.utc(2023, 1, 8, 9, 40, 0)

    vt.matches?(expected).should be_true
    vt.to_time(Time.utc(2022, 6, 21, 14, 9, 0)).should eq expected
    vt.succ(Time.utc(2022, 6, 21, 14, 9, 0)).should eq expected
  end

  it "resolves a negative week against the year it lands in" do
    # 2021-01-01 belongs to ISO year 2020, which has 53 weeks, while 2021 has
    # 52. Regression: `-39` was resolved against the hint's year to week 15,
    # while `#matches_date?` resolved it against the landing year to week 14 --
    # so the anchor was rejected and the whole of week 14 stepped over
    vt = VirtualTime.new hour: 11, minute: 10, second: 0, nanosecond: 0
    vt.week = -39

    vt.matches?(Time.utc(2021, 4, 5, 11, 10, 0)).should be_true
    vt.to_time(Time.utc(2021, 1, 1)).should eq Time.utc(2021, 4, 5, 11, 10, 0)
  end

  it "keeps both sides of a fall-back through a day walk and a distant match" do
    berlin = Time::Location.load("Europe/Berlin")

    # Regression: the day-of-week walk rebuilds the value from its wall clock,
    # and an ambiguous one comes back as the later of its two occurrences --
    # with nothing to put it back
    vt = VirtualTime.new hour: 2, minute: 30, second: 0, nanosecond: 0
    vt.day_of_week = 7
    vt.succ(Time.local(2020, 10, 24, 0, 0, 0, location: berlin))
      .should eq Time.utc(2020, 10, 25, 0, 30, 0).in(berlin) # 02:30 +02:00

    # Regression: whether a fall-back was in play was judged by comparing
    # offsets with the answer -- which can be a year away, with several
    # transitions in between, none of them the one that mattered
    vt = VirtualTime.new month: 10, day: 31, hour: 2, minute: 34, second: 0, nanosecond: 0
    first = Time.utc(2021, 10, 31, 0, 34, 0).in(berlin)  # 02:34 +02:00
    second = Time.utc(2021, 10, 31, 1, 34, 0).in(berlin) # 02:34 +01:00

    vt.matches?(first).should be_true
    vt.matches?(second).should be_true
    vt.succ(first).should eq second
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

  it "is not thrown off by a week constraint the date already satisfies" do
    utc = Time::Location::UTC
    base = Time.utc(2023, 11, 19, 2, 18, 0)

    # 2024-09-16 is a Monday, day 16, ISO week 38, so it satisfies every one of
    # these. Regression: whenever a week rule was given, the search anchored on
    # the current week's Monday -- behind the date it already had -- and the
    # anchor then skipped a whole year to stay in the future
    [nil, 1..53, 1..52, 6..49, 38].each do |week|
      vt = VirtualTime.new day: 16, hour: 15, minute: 0, second: 0, nanosecond: 0, location: utc
      vt.day_of_week = 1
      vt.week = week.as(VirtualTime::Virtual)

      vt.succ(base).should eq Time.utc(2024, 9, 16, 15, 0, 0)
    end
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

  it "adjusts a negative value once, not again when the sides are swapped" do
    vt = VirtualTime.new

    # Regression: swapping went back through `#matches?`, which adjusted the
    # already-adjusted values a second time -- with a max of 24 a `-30` became
    # `-6` and then `18`, spuriously equalling a literal 18
    vt.matches?(-30, 18, 24).should be_false
    vt.matches?(-30, [18], 24).should be_false
    vt.matches?([18], -30, 24).should be_false
  end

  it "treats a value that permits nothing as matching nothing" do
    wildcard = VirtualTime.new

    # Regression: only `false` propagated "never matches"; an empty list or
    # range fell through to `#default_match?` and claimed a match no `Time`
    # could satisfy
    [[] of Int32, (5...5), (20..10), false].each do |value|
      vt = VirtualTime.new
      vt.day = value.as(VirtualTime::Virtual)

      (1..31).none? { |day| vt.matches? Time.local(2024, 5, day) }.should be_true
      vt.matches?(wildcard).should be_false
    end
  end

  it "keeps matching commutative when default_match is false" do
    all_true = VirtualTime.new default_match: false
    all_true.year = true
    all_true.month = true
    all_true.day = true
    all_true.week = true
    all_true.day_of_week = true
    all_true.day_of_year = true
    all_true.hour = true
    all_true.minute = true
    all_true.second = true
    all_true.millisecond = true
    all_true.nanosecond = true

    all_nil = VirtualTime.new default_match: false

    # Regression: the `Bool` branch answered without consulting
    # `#default_match?`, so `nil` against `true` and `true` against `nil`
    # disagreed
    all_true.matches?(all_nil).should be_false
    all_nil.matches?(all_true).should be_false
  end

  it "leaves negative values alone when matching another VirtualTime" do
    # The number of days in a month is unknowable for a pattern, so a negative
    # value stays negative rather than being resolved against a max of one.
    # Regression: `day: -1` came out as `0`, a day no date has, and so matched
    # the literal `0`
    VirtualTime.new(day: -1).matches?(VirtualTime.new(day: -1)).should be_true
    VirtualTime.new(day: -1).matches?(VirtualTime.new(day: 0)).should be_false
    VirtualTime.new(week: -1).matches?(VirtualTime.new(week: 0)).should be_false
  end

  it "round-trips values that used to produce unreadable YAML" do
    # A fixed-offset location, which is what a timestamp parsed from an offset
    # carries. Regression: written as "+02:00", which `Time::Location.load`
    # rejects, so the document could not be read back
    fixed = Time.parse_rfc3339("2024-01-01T10:00:00+02:00").location
    vt = VirtualTime.new hour: 5, location: fixed
    VirtualTime.from_yaml(vt.to_yaml).location.should eq fixed

    # A negative step. Regression: written as "20..2/-2", which the parser
    # refused because it accepted only a positive step
    stepped = VirtualTime.new
    stepped.hour = 20.step to: 2, by: -2
    back = VirtualTime.from_yaml(stepped.to_yaml)
    (0..23).select { |hour| back.matches? Time.local(2024, 1, 1, hour) }
      .should eq (0..23).select { |hour| stepped.matches? Time.local(2024, 1, 1, hour) }

    # An empty list has no notation, and writing it as an empty scalar read
    # back as nil -- inverting "matches nothing" into "matches anything"
    empty = VirtualTime.new
    empty.day = [] of Int32
    expect_raises(ArgumentError, /empty list/) { empty.to_yaml }
  end

  it "counts location and default_match towards equality" do
    berlin = Time::Location.load("Europe/Berlin")
    new_york = Time::Location.load("America/New_York")
    moment = Time.local(2024, 1, 1, 5, 0, 0, location: berlin)

    here = VirtualTime.new hour: 5, location: berlin
    there = VirtualTime.new hour: 5, location: new_york

    # Regression: only the eleven value fields were compared, so two rules
    # matching disjoint sets of times were "equal" and collapsed in a Set
    here.matches?(moment).should be_true
    there.matches?(moment).should be_false
    (here == there).should be_false
    Set{here, there}.size.should eq 2

    always = VirtualTime.new hour: 5
    never = VirtualTime.new hour: 5, default_match: false
    (always == never).should be_false
  end

  it "keeps location out of #clear_time! and carries default_match through #expand" do
    berlin = Time::Location.load("Europe/Berlin")
    new_york = Time::Location.load("America/New_York")
    moment = Time.local(2024, 3, 6, 2, 0, 0, location: berlin) # 2024-03-05 20:00 in New York

    vt = VirtualTime.new day: 5, location: new_york
    vt.matches_date?(moment).should be_true

    # Regression: `#clear_time!` dropped the location, which converts the whole
    # timestamp and so bears on the date as well
    vt.clear_time!
    vt.matches_date?(moment).should be_true
    vt.clear!.location.should be_nil

    # Regression: `#expand` built its results with the default `default_match`,
    # so expanding a rule that matches nothing gave rules matching almost
    # everything
    VirtualTime.new(day: 1..2, default_match: false).expand.map(&.default_match?).should eq [false, false]
  end

  it "treats a value that permits nothing as matching nothing, on either side" do
    wildcard = VirtualTime.new
    always = VirtualTime.new hour: true

    # Regression: emptiness was only consulted for the left-hand value, so a
    # rule permitting nothing "matched" a wildcard when it was on the right
    [[] of Int32, (5...5), (20..10), false].each do |value|
      vt = VirtualTime.new
      vt.day = value.as(VirtualTime::Virtual)

      vt.matches?(wildcard).should be_false
      wildcard.matches?(vt).should be_false
    end

    empty_hour = VirtualTime.new
    empty_hour.hour = (20..10)
    always.matches?(empty_hour).should be_false
    empty_hour.matches?(always).should be_false
  end

  it "reads a descending stepped range in the right order" do
    descending = VirtualTime.new hour: 0, minute: 0, second: 0, millisecond: 0, nanosecond: 0
    descending.day = 20.step to: 2, by: -2

    ascending = VirtualTime.new hour: 0, minute: 0, second: 0, millisecond: 0, nanosecond: 0
    ascending.day = (2..20).step(2)

    # The two describe the same set of days
    (1..31).all? { |day| descending.matches?(Time.utc(2024, 1, day)) == ascending.matches?(Time.utc(2024, 1, day)) }
      .should be_true

    # Regression: materialization picked "first value at or after the wanted
    # one" from the list as given, which for a descending step is the largest
    from = Time.utc(2024, 1, 6, 12, 0, 0)
    descending.step(1.day, 1, from).first(5).to_a.should eq ascending.step(1.day, 1, from).first(5).to_a
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

  it "refuses a `false` millisecond and honours strict without a max" do
    vt = VirtualTime.new
    vt.millisecond = false

    # Regression: the millisecond guard tested truthiness, so `false` slipped
    # past the check every other field gets and produced a materialized value
    # the rule could never match
    expect_raises(ArgumentError, /isn't materializable/) do
      vt.materialize(Time.local(2024, 1, 1))
    end

    # Regression: a scalar `allowed` only replaced `wanted` when a max was
    # given, although `strict` is what asks for the replacement
    VirtualTime.new.materialize(5, 20, 0).should eq({5, 0})
    VirtualTime.new.materialize(5, 20, 0, 60).should eq({5, 1})
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
