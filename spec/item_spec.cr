require "./spec_helper"

describe Crystime::Item do
  #it "can parse timeunit" do
  # a= Crystime::Item.new
  # a.parse_timeunit("M").should eq(60)
  # a.parse_timeunit("m").should eq(60)
  # a.parse_timeunit("d").should eq(3600*24)
  # a.parse_timeunit("d").should eq(3600*24)
  #end

  it "honors start/stop dates" do
    date= Crystime::VirtualDate["2017-3-15"]
    item= Crystime::Item.new
    item.start= Crystime::VirtualDate["2017-1-1"]
    item.stop= Crystime::VirtualDate["2017-2-28"]
    item.due_on?(date).should be_nil

    date= Crystime::VirtualDate["2017-3-15"]
    item= Crystime::Item.new
    item.start= Crystime::VirtualDate["2017-6-1"]
    item.stop= Crystime::VirtualDate["2017-9-1"]
    item.due_on?(date).should be_nil

    date= Crystime::VirtualDate["2017-3-15 10:10:10"]
    item= Crystime::Item.new
    item.start= Crystime::VirtualDate["2017-1-1"]
    item.stop= Crystime::VirtualDate["2017-9-1"]
    item.due_on?(date).should be_true
  end

  it "honors due dates" do
    date= Crystime::VirtualDate["2017-3-15 10:10:10"]
    date.update!

    item= Crystime::Item.new
    item.start= Crystime::VirtualDate["2017-1-1"]
    item.stop= Crystime::VirtualDate["2017-9-1"]

    # @year    : Nil | ...
    # @month   : Nil | ...
    # @day     : Nil | ...
    # @day_of_week : Nil | ...
    # @jd  : Nil | ...
    # @hour    : Nil | ...
    # @minute  : Nil | ...
    # @second  : Nil | ...
    # @relative: Nil | Bool

    item.due_on?(date).should be_true

    vd= Crystime::VirtualDate.new
    item.due<< vd

    item.due_on?(date).should be_true

    # Year tests:

    vd.year= 2016
    item.due_on?(date).should be_nil

    vd.year= 2018
    item.due_on?(date).should be_nil

    vd.year= 2017
    item.due_on?(date).should be_true

    # Month tests:

    vd.month= 2
    item.due_on?(date).should be_nil

    vd.month= 4
    item.due_on?(date).should be_nil

    vd.month= 3
    item.due_on?(date).should be_true

    # Day tests:

    vd.day= 2
    item.due_on?(date).should be_nil

    vd.day= 16
    item.due_on?(date).should be_nil

    vd.day= 15
    #puts item.inspect
    #puts date.inspect
    item.due_on?(date).should be_true

    # Weekday tests:

    vd.year= nil
    vd.month= nil
    vd.day= nil
    item.due_on?(date).should be_true
    vd.day_of_week= 0
    #puts item.inspect
    #puts date.inspect
    item.due_on?(date).should be_nil
    vd.day_of_week= 2
    item.due_on?(date).should be_nil
    vd.day_of_week= 4
    item.due_on?(date).should be_nil
    vd.day_of_week= 3
    date= Crystime::VirtualDate["2017-3-15 10:10:10"]
    #puts item.inspect
    #puts date.inspect
    item.due_on?(date).should be_true

    # jd Day Number tests:

    vd.day_of_week= nil
    item.due_on?(date).should be_true
    vd.jd= 2457827
    item.due_on?(date).should be_nil
    vd.jd= 2457829
    item.due_on?(date).should be_nil
    vd.jd= 2457828
    item.due_on?(date).should be_true

    # Test with more than one due date:

    vd2= Crystime::VirtualDate.new
    item.due<< vd2
    # This matches because both vd and vd2 would match:
    item.due_on?(date).should be_true

    vd.jd= nil
    vd.day= 15
    # vd matches:
    item.due_on?(date).should be_true

    vd2.month= 3
    # Again both vd and vd2 now match:
    item.due_on?(date).should be_true

    vd.day= 3
    # vd is out, but vd2 should still be matching:
    item.due_on?(date).should be_true

    vd2.month= 9
    # Now it no longer matches:
    item.due_on?(date).should be_nil
  end

  # Identical copy of the above, but testing omit dates instead of due dates
  it "honors omit dates" do
    date= Crystime::VirtualDate["2017-3-15"]
    date.update!

    item= Crystime::Item.new
    item.start= Crystime::VirtualDate["2017-1-1"]
    item.stop= Crystime::VirtualDate["2017-9-1"]

    # @year    : Nil | ...
    # @month   : Nil | ...
    # @day     : Nil | ...
    # @day_of_week : Nil | ...
    # @jd  : Nil | ...
    # @hour    : Nil | ...
    # @minute  : Nil | ...
    # @second  : Nil | ...
    # @relative: Nil | Bool

    item.omit_on?(date).should be_nil

    vd= Crystime::VirtualDate.new
    item.omit<< vd

    item.omit_on?(date).should be_true

    # Year tests:

    vd.year= 2016
    item.omit_on?(date).should be_nil

    vd.year= 2018
    item.omit_on?(date).should be_nil

    vd.year= 2017
    item.omit_on?(date).should be_true

    # Month tests:

    vd.month= 2
    item.omit_on?(date).should be_nil

    vd.month= 4
    item.omit_on?(date).should be_nil

    vd.month= 3
    item.omit_on?(date).should be_true

    # Day tests:

    vd.day= 2
    item.omit_on?(date).should be_nil

    vd.day= 16
    item.omit_on?(date).should be_nil

    vd.day= 15
    item.omit_on?(date).should be_true

    # Weekday tests:

    vd.year= nil
    vd.month= nil
    vd.day= nil
    item.omit_on?(date).should be_true
    vd.day_of_week= 0
    item.omit_on?(date).should be_nil
    vd.day_of_week= 2
    item.omit_on?(date).should be_nil
    vd.day_of_week= 4
    item.omit_on?(date).should be_nil
    vd.day_of_week= 3
    item.omit_on?(date).should be_true

    # jd Day Number tests:

    vd.day_of_week= nil
    item.omit_on?(date).should be_true
    vd.jd= 2457827
    item.omit_on?(date).should be_nil
    vd.jd= 2457829
    item.omit_on?(date).should be_nil
    vd.jd= 2457828
    item.omit_on?(date).should be_true

    # Test with more than one omit date:

    vd2= Crystime::VirtualDate.new
    item.omit<< vd2
    # This matches because both vd and vd2 would match:
    item.omit_on?(date).should be_true

    vd.jd= nil
    vd.day= 15
    # vd matches:
    item.omit_on?(date).should be_true

    vd2.month= 3
    # Again both vd and vd2 now match:
    item.omit_on?(date).should be_true

    vd.day= 3
    # vd is out, but vd2 should still be matching:
    item.omit_on?(date).should be_true

    vd2.month= 9
    # Now it no longer matches:
    item.omit_on?(date).should be_nil
  end

  it "supports ranges" do
    date= Crystime::VirtualDate["2017-3-15"]

    item= Crystime::Item.new

    item.due_on?(date).should be_true

    vd= Crystime::VirtualDate.new
    item.due<< vd

    item.due_on?(date).should be_true

    vd.day= 14
    item.due_on?(date).should be_nil
    vd.day= 15
    item.due_on?(date).should be_true
    vd.day= 10..14
    item.due_on?(date).should be_nil
    vd.day= 13..19
    item.due_on?(date).should be_true
  end

  it "supports procs" do
    date= Crystime::VirtualDate["2017-3-15"]

    item= Crystime::Item.new

    vd= Crystime::VirtualDate.new
    item.due<< vd

    item.due_on?(date).should be_true

    vd.day= ->(val : Int32){true}
    item.due_on?(date).should be_true
    vd.day= ->(val : Int32){false}
    item.due_on?(date).should be_nil
  end


  it "returns 'on? # => true' on non-omitted due days" do
    date= Crystime::VirtualDate["2017-3-15"]

    item= Crystime::Item.new

    vd= Crystime::VirtualDate.new
    vd.year= 2017
    vd.month= 3
    vd.day= 15

    item.on?(date).should be_true
    item.due<< vd
    item.on?(date).should be_true
    item.omit<< vd
    item.on?(date).should be_false
  end

  it "reports shift amount on omitted due days" do
    date= Crystime::VirtualDate["2017-3-15"]

    item= Crystime::Item.new

    item.on?(date).should be_true

    vd= Crystime::VirtualDate.new
    vd.year= 2017
    vd.month= 3
    vd.day= 15
    item.due<< vd

    item.on?(date).should be_true

    vd2= Crystime::VirtualDate.new
    vd2.year= 2017
    vd2.month= 3
    vd2.day= 15

    vd3= Crystime::VirtualDate.new
    vd3.year= 2017
    vd3.month= 3
    vd3.day= 16

    item.omit<< vd2
    item.on?(date).should be_false

    item.omit_shift= Crystime::Span.new -1,0,0,0
    item.on?(date).should eq Crystime::Span.new -1,0,0,0
    item.omit_shift= Crystime::Span.new 4,0,0,0
    item.on?(date).should eq Crystime::Span.new 4,0,0,0

    item.omit<< vd3
    item.omit_shift= Crystime::Span.new 1,0,0,0
    item.on?(date).should eq Crystime::Span.new 2,0,0,0
  end

  it "reports false when effective omit larger than allowed boundaries" do
    date= Crystime::VirtualDate["2017-3-15"]

    item= Crystime::Item.new

    item.on?(date).should be_true

    vd3= Crystime::VirtualDate.new
    vd3.year= 2017
    vd3.month= 3
    vd3.day= 15..16

    limit_1day= Crystime::Span.new 1,0,0,0

    item.omit<< vd3
    item.omit_shift= Crystime::Span.new 1,0,0,0
    item.on?(date, limit_1day).should be_false
  end

  it "can check due/omit date/time separately" do
    date= Crystime::VirtualDate["2017-3-15 12:13:14"]

    item= Crystime::Item.new

    #vd3.year= 2017
    #vd3.month= 3
    #vd3.day= 15..16
    #vd3.hour= 1
    #vd3.minute= 2
    #vd3.second= 3

    vd3= Crystime::VirtualDate["2017-3-15 12:0:0"]
    raise "missing vd3!" unless vd3
    item.due<< vd3
    item.due_on?(date).should be_nil
    item.due_on_date?(date).should be_true
    item.due_on_time?(date).should be_nil

    vd4= Crystime::VirtualDate["2017-3-15"]
    raise "missing vd4!" unless vd4
    item.due<< vd4
    item.due_on?(date).should be_true

    vd5= Crystime::VirtualDate["12:13:14"]
    raise "missing vd5!" unless vd5
    item.due= [vd5]
    #puts date.inspect
    #puts vd5.inspect
    item.due_on?(date).should be_true

    vd6= Crystime::VirtualDate["12:13:15"]
    raise "missing vd6!" unless vd6
    item.due= [vd6]
    item.due_on?(date).should be_nil

    date= Crystime::VirtualDate["2017-3-15 1:2:3"]
    vd7= Crystime::VirtualDate["2017-3-18"]
    raise "missing vd7!" unless vd7
    item.due_on?(date).should be_nil
    item.due_on_date?(date).should be_true
    item.due=[vd7]
    item.due_on_date?(date).should be_nil
    item.due=[vd6]
    item.due_on_time?(date).should be_nil
    item.due=[vd7]
    item.due_on_time?(date).should be_true
  end

  it "can reschedule with higher granularity than days" do
    date= Crystime::VirtualDate["2017-3-15 12:13:14"]

    item= Crystime::Item.new

    item.due_on?(date).should be_true

    vd3= Crystime::VirtualDate.new
    raise "missing vd3!" unless vd3
    vd3.hour= 12
    item.omit<< vd3

    item.on?(date).should be_false

    item.omit_shift= Crystime::Span.new 0,0,-3,0
    item.on?(date).should eq Crystime::Span.new 0,0,-15,0
  end

  it "does range comparison properly" do
    item= Crystime::Item.new
    a= 6..10
    b= 2..4
    c= 4..6
    d= 6..8
    e= 5..7
    f= 7..8
    g= 8..10
    h= 10..12
    i= 9..11
    Crystime::Helpers.matches?( a, b).should be_false
    Crystime::Helpers.matches?( a, c).should be_false
    Crystime::Helpers.matches?( a, d).should be_true
    Crystime::Helpers.matches?( a, e).should be_false
    Crystime::Helpers.matches?( a, f).should be_true
    Crystime::Helpers.matches?( a, g).should be_true
    Crystime::Helpers.matches?( a, h).should be_false
    Crystime::Helpers.matches?( a, i).should be_false
  end

  it "can match virtual dates" do
    item= Crystime::Item.new

    vd= Crystime::VirtualDate["2017-3-15"]
    raise "missing vd!" unless vd
    item.due<< vd

    date= Crystime::VirtualDate["2017-3-15"]
    raise "no date!" unless date
    item.due_on_date?(date).should be_true
    date.year= nil
    date.month= nil
    date.day= nil
    item.due_on_date?(date).should be_true
    date.month= 3
    item.due_on_date?(date).should be_true
    date.month= 4
    item.due_on_date?(date).should be_nil
    date= Crystime::VirtualDate.new
    date.month= nil
    date.day= 15
    item.due_on_date?(date).should be_true
    date.day= 1
    item.due_on_date?(date).should be_nil
    date.day= 13..18
    #puts item.inspect
    #puts date.inspect
    item.due_on_date?(date).should be_true
    vd.day= 10..20
    item.due_on_date?(date).should be_true
    vd.day= 15
    date.day= 15
    item.due_on_date?(date).should be_true
    date.day= nil
    item.due_on_date?(date).should be_true
    date.month= 2
    item.due_on_date?(date).should be_nil
    date.month= 3
    item.due_on_date?(date).should be_true
    date.day= 13..18
    item.due_on_date?(date).should be_true

    vd2= Crystime::VirtualDate.new
    vd2.month= 3
    item.due=[vd2]
    date= Crystime::VirtualDate.new
    date.day= 13..18
    item.due_on_date?(date).should be_true
    date.month= 2
    item.due_on_date?(date).should be_nil
    date.month= 2..4
    item.due_on_date?(date).should be_true
    date.month= nil
    vd2.month= nil
    vd2.day= 15..18
    date.day= 15..18
    item.due_on_date?(date).should be_true
    date.day= 15..19
    item.due_on_date?(date).should be_nil
  end

  it "can shift on simple rules" do
    item= Crystime::Item.new
    due= Crystime::VirtualDate["2017-3-15"]
    date= Crystime::VirtualDate["2017-3-15"]
    omit= Crystime::VirtualDate["2017-3-15"]
    omit2= Crystime::VirtualDate["2017-3-14"]
    shift= Crystime::Span.new -1,0,0,0

    item.due= [due]
    item.on?(date).should be_true
    item.omit= [omit]
    item.on?(date).should be_false
    item.omit_shift= shift

    item.on?(date).should eq Crystime::Span.new -1,0,0,0
    item.omit<< omit2
    item.on?(date).should eq Crystime::Span.new -2,0,0,0

    item= Crystime::Item.new
    due= Crystime::VirtualDate["2017-3-15 01:34:0"]
    date= Crystime::VirtualDate["2017-3-15 01:34:0"]
    item.omit_shift= Crystime::Span.new 0,0,3,0
    omit= Crystime::VirtualDate.new
    omit.hour= 1
    item.due= [due]
    item.omit= [omit]
    item.on?(date).should eq Crystime::Span.new 0,0,27,0
  end
  it "can shift on complex rules" do
    item= Crystime::Item.new
    due= Crystime::VirtualDate.new
    due.day= 4
    date= Crystime::VirtualDate.new
    date.day= 4
    item.omit_shift= Crystime::Span.new 7,10,20,30
    omit= Crystime::VirtualDate.new
    omit.day= 4
    item.due= [due]
    item.omit= [omit]
    item.on?(date).should eq Crystime::Span.new 7,10,20,30

    item= Crystime::Item.new
    due= Crystime::VirtualDate.new
    due.day= 4
    date= Crystime::VirtualDate.new
    date.day= 4
    item.omit_shift= Crystime::Span.new 7,10,20,30
    omit= Crystime::VirtualDate.new
    omit.day= 3..14
    item.due= [due]
    item.omit= [omit]
    item.on?(date).should eq Crystime::Span.new 14,20,41,0

    item= Crystime::Item.new
    due= Crystime::VirtualDate.new
    due.day= 4..12
    date= Crystime::VirtualDate.new
    date.month= 4
    item.omit_shift= Crystime::Span.new 7,10,20,30
    omit= Crystime::VirtualDate.new
    omit.day= 3..14
    item.due= [due]
    item.omit= [omit]
    item.on?(date).should eq Crystime::Span.new 14,20,41,0
  end

  it "can check due on dates with ranges" do
    item= Crystime::Item.new
    due= Crystime::VirtualDate.new
    due.day= 4..12
    #item.omit_shift= Crystime::Span.new 7,10,20,30
    omit= Crystime::VirtualDate.new
    omit.day= 12
    item.due= [due]
    item.omit= [omit]

    date= Crystime::VirtualDate.new
    date.day= 8..11
    #puts date.inspect

    item.on?(date).should be_true

    date.day= 8..14

    item.on?(date).should be_nil

    dates= date.expand
    r= dates.map{ |d| item.on? d}
    r.should eq [true, true, true, true, false, nil, nil]

    # And another form of saying it:
    dates.map{ |d| item.on? d}.any?{ |x| x}.should be_true
  end

#    omit= Crystime::VirtualDate["2017-3-15"]
#    item.on?(date).should be_false
    #item.on?(date).should eq Crystime::Span.new 0,0,-15,0

#    vd2.day= 15
#    vd2.year= 2017 # XXX remove this and make sure it works without it too
#    vd3= Crystime::VirtualDate.new
#    item.omit_shift= Crystime::Span.new 0,0,-3,0
#    vd3.minute= 2..15
#    item.omit= [vd3]
#    expect_raises do item.on?(date).should eq Crystime::Span.new 0,0,-15,0 end
#    date.day= nil
#    date.minute= 14
#    p "Due: "+ item.due.inspect
#    p "Omit: "+ item.omit.inspect
#    p "Date: "+ date.inspect
  #end

  it "can shift til !due_on?( @omit) && due_on?( @shift)" do
    item= Crystime::Item.new
    due= Crystime::VirtualDate.new
    due.day= 4..12
    omit= Crystime::VirtualDate.new
    omit.day= 3..14
    shift= Crystime::VirtualDate.new
    shift.day= 23
    date= Crystime::VirtualDate.new
    date.day= 10
    item.omit_shift= Crystime::Span.new 1,0,0,0
    item.due= [due]
    item.omit= [omit]
    item.shift= [shift]
    item.on?(date).should eq Crystime::Span.new 13,0,0,0
  end

  it "respects max_shifts" do
    item= Crystime::Item.new
    due= Crystime::VirtualDate.new
    due.millisecond= 10
    omit= Crystime::VirtualDate.new
    omit.millisecond= 10..12
    date= Crystime::VirtualDate.new
    date.millisecond= 10
    item.omit_shift= Crystime::Span.new 0,0,0,0,1
    item.due= [due]
    item.omit= [omit]
    #puts omit.inspect
    #puts due.inspect
    #puts date.inspect
    item.on?(date, nil, nil, 30).should eq Crystime::Span.new 0,0,0,0,3
    shift= Crystime::VirtualDate.new
    shift.millisecond= 500
    #puts shift.inspect
    item.shift= [shift]
    item.on?(date, nil, nil, 30).should eq false
  end

  it "can match against Time objects" do
    item = Crystime::Item.new
    due = Crystime::VirtualDate.new
    due.month = 5
    due.day = 1..15
    item.due<< due

    item.on?( Time.new(2018,5,5)).should be_true
    item.on?( Time.new(2018,5,15)).should be_true
    item.on?( Time.new(2018,5,16)).should be_nil
  end

  it "works correctly with fold (negative values counting from the end)" do
    item = Crystime::Item.new
    due = Crystime::VirtualDate.new
    due.month = 5
    due.day = -2
    item.due<< due
    item.on?( Time.new(2018,5,30)).should be_true
    item.on?( Time.new(2018,5,31)).should be_nil
    item.on?( Crystime::VirtualDate.new(2018,5,30)).should be_true
    item.on?( Crystime::VirtualDate.new(2018,5,31)).should be_nil
  end

#  it "can remind" do
#   date= Crystime::VirtualDate["2017,3,15,  12,13,14)
#
#   item= Crystime::Item.new
#
#    vd3= Crystime::Wrap::Date.new(2017,3,10)
#    item.remind<< vd3
#
#    item.remind_on?(date-1.day).should be_nil
#    item.remind_on?(date+1.day).should be_nil
#    item.remind_on?(date).should be_true
# end
end
