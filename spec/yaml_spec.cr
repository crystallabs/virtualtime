require "./spec_helper"

describe Crystime::VirtualTime do
  it "can #to_yaml and #from_yaml" do
    date= Crystime::VirtualTime.new
    date.year= 2017
    date.month= 4..6
    date.day= true
    date.hour= 2..8/3

    y= date.to_yaml
    date2= Crystime::VirtualTime.from_yaml y
    y.should eq date2.to_yaml

    date.hour= 2...10/3

    y= date.to_yaml
    date2= Crystime::VirtualTime.from_yaml y
    y.should eq date2.to_yaml
  end

  it "converts to YAML" do
    vt= Crystime::VirtualTime.new
    vt.month = 3
    vt.day = [1,2]
    vt.hour = (10..20)
    vt.minute = (10..20).step(2)
    vt.second = true
    #vt.millisecond = ->( val : Int32) { true }
    vt.to_yaml.should eq "---\nmonth: 3\nday: 1,2\nhour: 10..20\nminute: 10,12,14,16,18,20\nsecond: true\n"
  end
  it "converts from YAML" do
    vt = Crystime::VirtualTime.from_yaml "---\nmonth: 3\nday: 1,2\nhour: 10..20\nminute: 10,12,14,16,18,20\nsecond: true\n"
    vt.month.should eq 3
    vt.day.should eq [1,2]
    vt.hour.should eq 10..20
  end
end
