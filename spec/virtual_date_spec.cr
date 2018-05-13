require "./spec_helper"

describe Crystime do
  it "contains good hashes" do
    a= Crystime::VirtualDate::W2I["SUN"]
    a.should eq 0
    a= Crystime::VirtualDate::W2I["SAT"]
    a.should eq 6
    a= Crystime::VirtualDate::M2I["JAN"]
    a.should eq 1
    a= Crystime::VirtualDate::M2I["DEC"]
    a.should eq 12
  end
  it "can be initialized" do
    a= Crystime::VirtualDate.new
    a.year.should eq nil
    a.month.should eq nil
    a.day.should eq nil
    a.weekday.should eq nil
    #a.relative.should eq nil
    a.jd.should eq nil
  end
  it "returns self when self" do
    a= Crystime::VirtualDate.new
    b= Crystime::VirtualDate[a]
    b.should eq a
  end
  it "parses iso8601 datetime when string" do
    # XXX ignores the timezone
    a= Crystime::VirtualDate["2017-06-24T18:23:47+00:00"]
    raise "a is nil!" unless a
    a.year.should eq 2017
    a.month.should eq 6
    a.day.should eq 24
    a.is_a?( Crystime::VirtualDate).should eq(true)
  end
  it "can parse time with milliseconds" do
    a= Crystime::VirtualDate["1:2:3.40000"]
    a.hour.should eq 1
    a.minute.should eq 2
    a.second.should eq 3
    a.millisecond.should eq 40000
  end
  it "can parse weekday names" do
    a= Crystime::VirtualDate["Mon"]
    a.weekday.should eq 1
  end
  it "can parse month names" do
    a= Crystime::VirtualDate["Aug"]
    a.month.should eq 8
  end
  it "can parse combinations of supported string pieces" do
    vd = Crystime::VirtualDate["2018 wed 12:00:00"]
    vd.weekday.should eq 3
    vd.hour.should eq 12
  end
  it "supports all 7 documented types of values" do
    a = Crystime::VirtualDate.new
    a.year = nil # Remains unspecified, matches everything it is compared with
    a.month = 3
    a.day = [1,2]
    a.hour = (10..20)
    a.minute = (10..20).step(2)
    a.second = true
    a.millisecond = ->( val : Int32) { return true }
  end
  it "has getter for @ts (materialization ability)" do
    a = Crystime::VirtualDate.new
    a.year = nil # Remains unspecified, matches everything it is compared with
    a.month = 3
    a.day = [1,2]
    a.hour = (10..20)
    a.minute = (10..20).step(2)
    a.second = true
    a.millisecond = ->( val : Int32) { return true }

    a.ts.should eq [nil, true, false, false, false, false, false]
  end
end
