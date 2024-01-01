require "spec"
require "../src/virtualtime"

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

  it "honors default_match?" do
    vt = VirtualTime.new
    vt.matches?(Time.local).should be_true
    vt.default_match = false
    vt.matches?(Time.local).should be_false
  end

  it "can adjust timezone for Times" do
    time = Time.local year: 2020, month: 1, day: 15, location: Time::Location.load("Europe/Berlin")
    vt = VirtualTime.new location: Time::Location.load("America/New_York")
    time2 = vt.adjust_location time
    time2.should eq time.in vt.location.not_nil!

    vt = VirtualTime.new location: Time::Location.load("Europe/Berlin")
    vt2 = VirtualTime.new location: Time::Location.load("America/New_York")
    expect_raises(ArgumentError) do
      vt.adjust_location vt2
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
      vt.matches?(nil, ->{ false }, max).should be_true
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
      vt.matches?(true, ->{ false }, max).should be_true

      vt.matches?(false, nil, max).should be_false
      vt.matches?(false, false, max).should be_false
      vt.matches?(false, true, max).should be_false
      vt.matches?(false, 0, max).should be_false
      vt.matches?(false, 15, max).should be_false
      vt.matches?(false, [1, 2, 3], max).should be_false
      vt.matches?(false, 1..10, max).should be_false
      vt.matches?(false, (1..10).step(3), max).should be_false
      vt.matches?(false, ->{ false }, max).should be_false
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
end
