require "./spec_helper"

describe Crystime::VirtualTime do
  it "contains good hashes" do
    a= Crystime::Helpers::W2I["SUN"]
    a.should eq 0
    a= Crystime::Helpers::W2I["SAT"]
    a.should eq 6
    a= Crystime::Helpers::M2I["JAN"]
    a.should eq 1
    a= Crystime::Helpers::M2I["DEC"]
    a.should eq 12
  end
  it "can be initialized" do
    a= Crystime::VirtualTime.new
    a.year.should eq nil
    a.month.should eq nil
    a.day.should eq nil
    a.day_of_week.should eq nil
    #a.relative.should eq nil
    a.jd.should eq nil
  end
  it "returns self when self" do
    a= Crystime::VirtualTime.new
    b= Crystime::VirtualTime[a]
    b.should eq a
  end
  it "parses iso8601 datetime when string" do
    # XXX ignores the timezone
    a= Crystime::VirtualTime["2017-06-24T18:23:47+00:00"]
    a.is_a?( Crystime::VirtualTime).should eq(true)
    #raise "a is nil!" unless a
    a.year.should eq 2017
    a.month.should eq 6
    a.day.should eq 24
  end
  it "can parse time with milliseconds" do
    a= Crystime::VirtualTime["1:2:3.40000"]
    a.hour.should eq 1
    a.minute.should eq 2
    a.second.should eq 3
    a.millisecond.should eq 40000
  end
  it "can parse day_of_week names" do
    a= Crystime::VirtualTime["Mon"]
    a.day_of_week.should eq 1
  end
  it "can parse month names" do
    a= Crystime::VirtualTime["Aug"]
    a.month.should eq 8
  end
  it "can parse combinations of supported string pieces" do
    vd = Crystime::VirtualTime["2018 wed 12:00:00"]
    vd.day_of_week.should eq 3
    vd.hour.should eq 12
  end
  it "supports all 7 documented types of values" do
    a = Crystime::VirtualTime.new
    a.year = nil # Remains unspecified, matches everything it is compared with
    a.month = 3
    a.day = [1,2]
    a.hour = (10..20)
    a.minute = (10..20).step(2)
    a.second = true
    a.millisecond = ->( val : Int32) { return true }
  end
  it "has getter for @ts (materialization ability)" do
    a = Crystime::VirtualTime.new
    a.year = nil # Remains unspecified, matches everything it is compared with
    a.month = 3
    a.day = [1,2]
    a.hour = (10..20)
    a.minute = (10..20).step(2)
    a.second = true
    a.millisecond = ->( val : Int32) { return true }

    a.ts.should eq [nil, true, false, false, false, false, false]
  end

  it "knows Julian Day Number" do
    vd= Crystime::VirtualTime.new
    vd.year= 2017
    vd.month= 6
    vd.day= 28
    vd.to_jd.should eq 2457933
  end

  it "can materialize!" do
    vd= Crystime::VirtualTime.new
    vd.materialize!
    vd.to_tuple.should eq( {1,1,1,1,1721426,0,0,0,0})
  end

  it "resets day_of_week/jd after de-materializing" do
    v= Crystime::VirtualTime.new
    v.year= 2017
    v.month= 12
    v.day= 1
    v.jd.should eq 2458089
    v.day_of_week.should eq 5
    v.day= nil
    v.jd.should eq nil
    v.day_of_week.should eq nil
  end

  it "can expand VTs" do
    d= Crystime::VirtualTime.new
    d.year= 2017
    #d.month= 1..3
    d.day= 14..17
    d.hour= 9..12
    d.millisecond= 1
    d.expand.should eq [
      Crystime::VirtualTime.from_array( [2017, nil, 14, 9,  nil, nil, 1]),
      Crystime::VirtualTime.from_array( [2017, nil, 14, 10, nil, nil, 1]),
      Crystime::VirtualTime.from_array( [2017, nil, 14, 11, nil, nil, 1]),
      Crystime::VirtualTime.from_array( [2017, nil, 14, 12, nil, nil, 1]),
      Crystime::VirtualTime.from_array( [2017, nil, 15, 9,  nil, nil, 1]),
      Crystime::VirtualTime.from_array( [2017, nil, 15, 10, nil, nil, 1]),
      Crystime::VirtualTime.from_array( [2017, nil, 15, 11, nil, nil, 1]),
      Crystime::VirtualTime.from_array( [2017, nil, 15, 12, nil, nil, 1]),
      Crystime::VirtualTime.from_array( [2017, nil, 16, 9,  nil, nil, 1]),
      Crystime::VirtualTime.from_array( [2017, nil, 16, 10, nil, nil, 1]),
      Crystime::VirtualTime.from_array( [2017, nil, 16, 11, nil, nil, 1]),
      Crystime::VirtualTime.from_array( [2017, nil, 16, 12, nil, nil, 1]),
      Crystime::VirtualTime.from_array( [2017, nil, 17, 9,  nil, nil, 1]),
      Crystime::VirtualTime.from_array( [2017, nil, 17, 10, nil, nil, 1]),
      Crystime::VirtualTime.from_array( [2017, nil, 17, 11, nil, nil, 1]),
      Crystime::VirtualTime.from_array( [2017, nil, 17, 12, nil, nil, 1])
    ]
  end

  it "can initialize from array" do
    a= Crystime::VirtualTime.new
    a.month= 1..3
    vds= a.expand
    vds[0].month.should eq 1
    vds[1].month.should eq 2
  end

  #it "is in UTC" do
  #  Crystime::VirtualTime.new.utc?.should be_true
  #end

  it "does set Ymd from jd" do
    vd= Crystime::VirtualTime.new
    vd.day_of_week.should eq nil
    vd.jd= 2457828
    vd.year.should eq 2017
    vd.month.should eq 3
    vd.day.should eq 15
    vd.day_of_week.should eq 3
  end

  it "does set jd from Ymd" do
    vd= Crystime::VirtualTime.new
    vd.year= 2017
    vd.month= 3
    vd.day= 17

    vd.jd.should eq 2457830
    vd.day_of_week.should eq 5
  end

  it "knows materialized virtual dates" do
    vd= Crystime::VirtualTime.new
    vd.materialized?.should be_false
    vd.year= 1
    vd.month= 2
    vd.day= 3
    vd.materialized?.should be_false
    vd.hour= 4
    vd.minute= 5
    vd.second= 6
    vd.materialized?.should be_false
    vd.millisecond= 7
    vd.materialized?.should be_true
    vd.second= 9..12
    vd.materialized?.should be_false
    vd.second= 1
    vd.materialized?.should be_true
    vd.second= nil
    vd.materialized?.should be_false
  end

  it "changes day_of_week according to Ymd" do
    vd= Crystime::VirtualTime["2017-07-02"]
    #puts vd.inspect
    vd.day_of_week.should eq 0
    vd.day= 1
    vd.day_of_week.should eq 6
  end

  it "setting day_of_week does not affect Ymd" do
    vd= Crystime::VirtualTime["2017-07-02"]
    vd.day_of_week= 4
    vd.day_of_week.should eq 4
    vd.day.should eq 2
  end

  it "can subtract materializable VTs" do
    vd1= Crystime::VirtualTime["2018-04-02"]
    vd2= Crystime::VirtualTime["2018-04-01"]
    (vd1-vd2).should eq Crystime::Span.new(1,0,0,0,0)
  end

  it "cannot subtract non-materializable VTs" do
    vd1= Crystime::VirtualTime.new
    vd1.month=3..5
    vd2= Crystime::VirtualTime.new
    vd2.month=4..5
    expect_raises ArgumentError, "" {
      (vd1-vd2).should eq 1
    }
  end
  it "performs comparison commutatively" do
    a = Crystime::VirtualTime.new
    a.year = nil # Remains unspecified, matches everything it is compared with
    a.month = 3
    a.day = [1,2]
    a.hour = (10..20)
    a.minute = (10..20).step(2)
    a.second = true
    a.millisecond = ->( val : Int32) { return true }

    b = Crystime::VirtualTime.new
    b.year = 1
    b.month = 3
    b.day = 2
    b.hour = 12
    b.minute = 16
    b.second = nil
    b.millisecond = 1

    a.matches?(b).should be_true
    b.matches?(a).should be_true
  end

  it "can materialize using a hint" do
    vt= Crystime::VirtualTime.new
    vt.day= 15
    hint= Crystime::VirtualTime.new 1,2,3,4,5,6,7
    vt.materialize!(hint).to_array.should eq [1,2,15,4,5,6,7]
  end

end
