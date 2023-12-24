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
    vt = VirtualTime.new nanosecond: nil

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
    vt.to_yaml.should eq "---\nmonth: 3\nday: 1,2\nhour: 10..20\nminute: 10,12,14,16,18,20\nsecond: true\nnanosecond: 0\nlocation: Europe/Berlin\n"
  end
  it "converts from YAML" do
    vt = VirtualTime.from_yaml "---\nmonth: 3\nday: 1,2\nhour: 10..20\nminute: 10,12,14,16,18,20\nsecond: true\nlocation: Europe/Berlin\n"
    vt.month.should eq 3
    vt.day.should eq [1, 2]
    vt.hour.should eq 10..20
    vt.second.should eq true
    vt.location.should eq Time::Location.load("Europe/Berlin")
  end

  it "does range comparison properly" do
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
    VirtualTime.matches?(a, b).should be_false
    VirtualTime.matches?(a, c).should be_true
    VirtualTime.matches?(a, d).should be_true
    VirtualTime.matches?(a, e).should be_true
    VirtualTime.matches?(a, f).should be_true
    VirtualTime.matches?(a, g).should be_true
    VirtualTime.matches?(a, h).should be_true
    VirtualTime.matches?(a, i).should be_true
    VirtualTime.matches?(a, j).should be_false
  end
end
