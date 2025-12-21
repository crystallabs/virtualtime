require "spec"
require "../src/virtualtime"

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
    vt.year.should eq nil
    vt.month.should eq nil
    vt.day.should eq nil
    vt.day_of_week.should eq nil
    vt.location.should eq nil
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
    vt.to_yaml.should eq "---\nmonth: 3\nday: 1,2\nhour: 10..20\nminute: 10,12,14,16,18,20\nsecond: true\nlocation: Europe/Berlin\ndefault_match: true\n"
  end

  it "converts from YAML" do
    vt = VirtualTime.from_yaml "---\nmonth: 3\nday: 1,2\nhour: 10..20\nminute: 10,12,14,16,18,20\nsecond: true\nlocation: Europe/Berlin\ndefault_match: false\n"
    vt.month.should eq 3
    vt.day.should eq [1, 2]
    vt.hour.should eq 10..20
    vt.second.should eq true
    vt.location.should eq Time::Location.load("Europe/Berlin")
    vt.default_match?.should eq false
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
    time2.should eq time.in vt.location.not_nil!
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
    (vt <=> t).should eq 1
    vt.year = 1970
    (vt == t).should be_false
    (vt <=> t).should eq -1
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
    v_true = ->(v : Int32) { true }
    v_false = ->(v : Int32) { false }
    v_ge_10 = ->(v : Int32) { v >= 10 }

    vt.matches?(v_true, 0, nil).should be_true
    vt.matches?(v_false, 0, nil).should be_false
    vt.matches?(v_ge_10, 0, nil).should be_false
    vt.matches?(v_ge_10, 20, nil).should be_true
  end

  it "can't do matches?(VirtualProc, VirtualProc, max)" do
    vt = VirtualTime.new
    v_true = ->(v : Int32) { true }
    expect_raises(ArgumentError) {
      vt.matches? v_true, v_true
    }
  end

  it "does not support Proc serialization to YAML" do
    vt = VirtualTime.new
    vt.second = ->(v : Int32) { v > 10 }
    expect_raises(Exception) {
      yaml = vt.to_yaml
    }
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

  describe VirtualTime::Search do
    describe ".shift_from_base" do
      it "returns zero-based forward delta to first unblocked time" do
        t0 = Time.local(2023, 5, 10, 10, 0, 0)

        # Block exactly at t0, unblock at +2 minutes
        delta = VirtualTime::Search.shift_from_base(t0, 1.minute, max_shift: nil, max_shifts: 10) do |t|
          t <= t0 + 1.minute
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
    end

    describe ".is_shifted_from_base?" do
      it "returns true when target is reachable via inverse shifting" do
        t0 = Time.local(2023, 5, 10, 10, 0, 0)
        target = t0 + 2.hours

        reachable = VirtualTime::Search.is_shifted_from_base?(target, 1.hour, max_shift: 3.hours, max_shifts: 5) do |base|
          # Base is considered schedulable but shifted by +2h
          if base == t0
            2.hours
          else
            nil
          end
        end

        reachable.should be_true
      end

      it "returns false when inverse search exceeds bounds" do
        t0 = Time.local(2023, 5, 10, 10, 0, 0)
        target = t0 + 5.hours

        reachable = VirtualTime::Search.is_shifted_from_base?(target, 1.hour, max_shift: 2.hours, max_shifts: 10) do |base|
          # Only bases at least 5 hours away produce a shift,
          # which exceeds max_shift and must be rejected.
          if (target - base) >= 5.hours
            5.hours
          else
            nil
          end
        end

        reachable.should be_false
      end

      it "returns true when inverse shift delta is exactly equal to max_shift" do
        t0 = Time.local(2023, 5, 10, 10, 0, 0)
        target = t0 + 2.hours

        reachable = VirtualTime::Search.is_shifted_from_base?(target, 1.hour, max_shift: 2.hours, max_shifts: 5) do |base|
          # Only the exact base produces the exact boundary delta.
          if base == t0
            2.hours
          else
            nil
          end
        end

        reachable.should be_true
      end

      it "returns false when no base produces the target" do
        t0 = Time.local(2023, 5, 10, 10, 0, 0)
        target = t0 + 1.hour

        reachable = VirtualTime::Search.is_shifted_from_base?(target, 30.minutes, max_shift: 2.hours, max_shifts: 5) do |_|
          45.minutes
        end

        reachable.should be_false
      end

      it "returns true when inverse shift delta is exactly -max_shift (negative boundary)" do
        t0 = Time.local(2023, 5, 10, 10, 0, 0)
        target = t0 - 2.hours

        reachable = VirtualTime::Search.is_shifted_from_base?(target, -1.hour, max_shift: 2.hours, max_shifts: 5) do |base|
          # Only the exact base produces the exact negative boundary delta.
          if base == t0
            -2.hours
          else
            nil
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

        reachable = VirtualTime::Search.is_shifted_from_base?(target, 1.hour, max_shift: 2.hours, max_shifts: 5) do |b|
          if b == base
            2.hours
          else
            nil
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

        reachable = VirtualTime::Search.is_shifted_from_base?(target, -1.hour, max_shift: 2.hours, max_shifts: 5) do |b|
          if b == base
            -2.hours
          else
            nil
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

          reachable = VirtualTime::Search.is_shifted_from_base?(target, step, max_shift: max_shift, max_shifts: max_shifts) do |_|
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
            VirtualTime::Search.is_shifted_from_base?(target, step, max_shift: max_shift, max_shifts: max_shifts) do |b|
              b == base ? delta : nil
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

          delta = VirtualTime::Search.shift_from_base(start, step, max_shift: max_shift, max_shifts: max_shifts) do |t|
            t < start + blocked_for
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

        reachable = VirtualTime::Search.is_shifted_from_base?(target, step, max_shift: max_shift, max_shifts: max_shifts) do |b|
          b == base ? delta : nil
        end

        if reachable && delta.abs > max_shift
          raise "Invariant violation"
        end
      end
    rescue
      shrunk =
        shrink_case(base, step, delta, max_shift, max_shifts) do |b, s, d|
          t = b + d

          VirtualTime::Search.is_shifted_from_base?(t, s, max_shift: max_shift, max_shifts: max_shifts) { |bb| bb == b ? d : nil } && d.abs > max_shift
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
      ].map { |z| Time::Location.load(z) }

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

        reachable = VirtualTime::Search.is_shifted_from_base?(target, step, max_shift: max_shift, max_shifts: max_shifts) do |b|
          b == base ? delta : nil
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
