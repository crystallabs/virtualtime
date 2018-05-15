# VirtualTime is a flexible representation of a date, allowing
# it to be full, partial, contain ranges, procs, etc.
# It also offers out of the box support for comparing and
# matching VirtualTimes.

require "yaml"

module Crystime
  class VirtualTime

    include Comparable(self)
    include Comparable(Time)

    # XXX Use Int instead of Int32 when it becomes possible in Crystal
    alias Virtual = Nil | Int32 | Bool | Range(Int32, Int32) | Enumerable(Int32) | Proc(Int32, Bool)

    #getter month, year, day, day_of_week, jd, hour, minute, second, millisecond
    #@month :       Virtual?
    #@year :        Virtual?
    #@day :         Virtual?
    #@day_of_week : Virtual?
    #@jd :          Virtual?
    #@hour :        Virtual?
    #@minute :      Virtual?
    #@second :      Virtual?
    #@millisecond : Virtual?
    YAML.mapping({
      # Date-related properties
      month:       { type: Virtual, nilable: true, setter: false, converter: Crystime::VirtualTimeConverter},
      year:        { type: Virtual, nilable: true, setter: false, converter: Crystime::VirtualTimeConverter},
      day:         { type: Virtual, nilable: true, setter: false, converter: Crystime::VirtualTimeConverter},
      day_of_week: { type: Virtual, nilable: true, setter: false, converter: Crystime::VirtualTimeConverter},
      jd:          { type: Virtual, nilable: true, setter: false, converter: Crystime::VirtualTimeConverter},
      # Time-related properties
      hour:        { type: Virtual, nilable: true, setter: false, converter: Crystime::VirtualTimeConverter},
      minute:      { type: Virtual, nilable: true, setter: false, converter: Crystime::VirtualTimeConverter},
      second:      { type: Virtual, nilable: true, setter: false, converter: Crystime::VirtualTimeConverter},
      millisecond: { type: Virtual, nilable: true, setter: false, converter: Crystime::VirtualTimeConverter},
    })

    #property :relative
    #@relative: Nil | Bool

    property ts
    # "ts" is a variable which keeps track of which fields were actually specified in VirtualTime.
    # E.g., if a user specifically sets seconds value (even if 0), then field 5 will be true. Otherwise, it will be false.
    # This is important for matching VirtualTimes, because if one VirtualTime has ts[5] set to nil (not specified), and
    # the other has ts[5] set to true, that will be considered a match. (An unspecified value matches all possible values.)
    #      0    1     2     3     4     5     6
    #      year month day   hour  min   sec   ms
    @ts= [ nil, nil,  nil,  nil,  nil,  nil,  nil] of Bool?

    #protected getter time

    # Empty constructor. Must be here since when fields are defined, the
    # default empty constructor is not created.
    def initialize
    end

    # Similar to Time constructor.
    # Fields are set via properties to trigger corresponding methods.
    def initialize(year, month, day, hour= nil, minute= nil, second= nil, millisecond= nil)
      self.year= year
      self.month= month
      self.day= day
      self.hour= hour
      self.minute= minute
      self.second= second
      self.millisecond= millisecond
    end

    def self.now
      t= Time.now
      from_array [t.year, t.month, t.day, t.hour, t.minute, t.second, t.millisecond]
    end

    def self.from_array( arg)
      r= new
      r.year, r.month, r.day, r.hour, r.minute, r.second, r.millisecond= arg[0..6]
      r
    end
    def to_array
      [self.year, self.month, self.day, self.hour, self.minute, self.second, self.millisecond]
    end

    def dup
      self2= super
      self2.ts= self.ts.dup
      self2
    end

    # XXX should boolean value be treated as materializable and have ts=true?
    def year=( v)        @year= v;   @ts[0]= v.is_a?( Int) ? true : v.nil? ? nil : false; update! end
    def month=( v)       @month= v;  @ts[1]= v.is_a?( Int) ? true : v.nil? ? nil : false; update! end
    def day=( v)         @day= v;    @ts[2]= v.is_a?( Int) ? true : v.nil? ? nil : false; update! end
    def hour=( v)        @hour= v;   @ts[3]= v.is_a?( Int) ? true : v.nil? ? nil : false; end
    def minute=( v)      @minute= v; @ts[4]= v.is_a?( Int) ? true : v.nil? ? nil : false; end
    def second=( v)      @second= v; @ts[5]= v.is_a?( Int) ? true : v.nil? ? nil : false; end
    def millisecond=( v) @millisecond= v; @ts[6]= v.is_a?( Int) ? true : v.nil? ? nil : false; end
    # Weekday does not affect actual date, only adds a constraint.
    def day_of_week=( v)
      @day_of_week= v
      true
    end

    # Julian Day-related methods:

    # Julian Day Number does affect actual date, but is not used in calculations.
    def jd=( v)
      from_jd! if @jd= v
      true
    end
    def from_jd!
      raise Crystime::Errors.invalid_jd unless jd= from_jd
      @year, @month, @day= jd[0], jd[1], jd[2]
      @ts[0..2]= [true,true,true]
      update!( jd: false)
      true
    end
    # Creates VirtualTime from Julian Day Number.
    def from_jd
      jd= @jd
      if jd.nil?
        self.year= nil
        self.month= nil
        self.day= nil
        return
      elsif !jd.is_a? Int
        raise Crystime::Errors.invalid_jd
      end
      # https://en.wikipedia.org/wiki/Julian_day
      y= 4716; j= 1401; m= 2; n= 12; r= 4; p= 1461;
      v= 3; u= 5; s= 153; w= 2; b= 274277; c= -38;
      f = jd + j + (((4 * jd + b) / 146097) * 3) / 4 + c
      e = r * f + v
      g = (e % p) / r
      h = u * g + w
      gd = (h % s) / u + 1
      gm = ((h / s + m) % n) + 1
      gy = (e / p) - y + (n + m - gm) / n
      {gy, gm, gd}
    end
    # Creates Julian Day Number from VirtualTime, when possible. Raises otherwise.
    def to_jd
      if @ts[0]&& @ts[1]&& @ts[2]
        a= ((14-@month.as( Int))/12).floor
        y= @year.as( Int)+ 4800- a
        m= @month.as( Int)+ 12*a- 3
        @day.as( Int)+ ((153*m+ 2)/5).floor+ 365*y+ (y/4).floor- (y/100).floor+ (y/400).floor- 32045
      else
        raise "Can't convert non-materializable date to Julian Day Number"
      end
    end

    # Called when year, month, or day are re-set and we need to re-calculate which day_of_week and
    # Julian Day Number the new date corresponds to. This is only filled if Y/m/d is specified.
    # If it is not specified (meaning that the VirtualTime does not refer to a specific date),
    # then they are set to nil.
    # In the case where the change is caused by a jd that was just set, a 'jd: false' parameter
    # could be passed not to touch jd again, even though there's no harm even if it is modified.
    # XXX check whether update! is properly called (and/or code works correctly) when VTs are summed
    # or subtracted.
    def update!(jd = true)
      if @ts[0]&& @ts[1]&& @ts[2]
        #puts "date is: "+ self.inspect

        # XXX this code seems like generic functionality, not something to put into update!
        m= @month.as Int
        if m< 0
          m= 13+ m
        end
        d= @day.as Int
        if d< 0
          d= Time.days_in_month(@year.as(Int), m)+ 1+ d
        end

        t= Time.new(@year.as( Int), m, d, kind: Time::Kind::Utc)
        @day_of_week= t.day_of_week.to_i
        @jd= to_jd if jd
      else
        @day_of_week= @jd= nil
      end
      true
    end

    # Expands a partial VirtualTime into a materialized/specific date/time.
    def expand
      [@year, @month, @day, @hour, @minute, @second, @millisecond].expand.map{ |v| Crystime::VirtualTime.from_array v}
    end

    # Helpers for interoperability with self

    def <=>( other : self) to_time<=>other.to_time end
    def +( other : self) self+ other.to_time end
    def -( other : self) self- other.to_time end

    # Helpers for interoperability with Time

    def <=>( other : Time) to_time<=>other end
    # Btw, this is not supported with Time struct. (I.e. you can do Time-Time, but not Time+Time)
    def +( other : Time)
      self_time= self.to_time
      Span.new(
        seconds: self_time.total_seconds + other.total_seconds,
        nanoseconds: self_time.nanosecond + other.nanosecond,
      )
    end
    def -( other : Time)
      self_time= self.to_time
      Span.new(
        seconds: self_time.total_seconds - other.total_seconds,
        nanoseconds: self_time.nanosecond - other.nanosecond,
      )
    end

    # Helpers for interoperability with Crystime::Span and Time::Span

    # XXX see what to do about this: after +, VT essentially becomes fully materialized, which isn't ideal
    def +( other : Span | Time::Span)
      self_time= self.to_time
      t= self_time+ other
      self.year= t.year
      self.month= t.month
      self.day= t.day
      self.hour= t.hour
      self.minute= t.minute
      self.second= t.second
      self.millisecond= t.millisecond
      self
    end
    # XXX add tests for @ts=[...] looking correct after VirtualTime+ Span
    def -( other : Span | Time::Span) self+ -other end

    # End of helpers

    # Converts a VT to Time. If VT is non-materializable, the process raises an exception.
    def to_time(kind = Time::Kind::Utc)
      if @ts.any?{ |x| x== false}
        raise Crystime::Errors.cant_materialize
      end

      obj= self
      unless @ts.all?{ |x| x== true}
        # XXX Call materialize! here with a 'hint' argument passed from user configuration
        obj= obj.dup.materialize!
      end

      Time.new(
        obj.year.as(Int),
        obj.month.as(Int),
        obj.day.as(Int),
        hour: obj.hour.as(Int),
        minute: obj.minute.as(Int),
        second: obj.second.as(Int),
        nanosecond: obj.millisecond.as(Int)* 1_000_000,
        kind: kind
      )
    end

    ## Checks if this VT is in UTC. Responds with fixed value.
    #def utc?() true end

    def materialized?
      # XXX do we consider materialized dates those with all values true, or we need
      # to split materialized? into materialized_date? and materialized_time?
      #@ts[0..2]= [true,true,true]
      @ts.all?{ |x| x== true}
    end
    def materialize!( hint= VirtualTime.new(1,1,1,0,0,0,0))
      #t= Time.now
      # XXX modify so that if value is proc, we call it;
      # if value is range, we take range.begin, etc.
      # It's OK to use these values here because if a person does not
      # want to materialize to these probably-not-useful values,
      # they simply need to provide 'hint' as argument.
      # XXX but do solve the case of field== false. Right now we override
      # those with these default values, which is incorrect. (E.g. a 
      # range needs to materialize to range.begin, not to 1 or 0).
      merge hint
      # XXX But work is not done here. This function needs to actually be
      # rewritten so that each field is individually materialized, and that
      # via a hint we can specify how the process should work even in more
      # detail. (Like, to materialize 3..9 to be either 3, or 9, or middle (6)
      # and so on.)
    end

    # Merges a VT or Time into self. Uses rule of left precedent (if self already has a value for a particular field, it is not overwritten).
    # XXX possibly replace with macro? Possibly change logic?
    def merge( other : self)
      self.year        ||= other.year
      self.month       ||= other.month
      self.day         ||= other.day
      self.hour        ||= other.hour
      self.minute      ||= other.minute
      self.second      ||= other.second
      self.millisecond ||= other.millisecond
      self
    end

    def to_tuple
      { @year, @month, @day, @day_of_week, @jd, @hour, @minute, @second, @millisecond}
    end

    # Parses string and produces VirtualTime.
    def self.[]( date)
      return date if date.is_a? self
      #puts "TRYING TO PARSE #{date}"

      #formats= {
      #  "%FT%X%z",
      #  "%F %T %z",
      #  "%F %T",
      #  "%F",
      #  "%T %z",
      #  "%T",
      #}

      r= new
      ret= false

      if m= date.match /(?<year>\d{4})[\-\/\.](?<month>\d{1,2})[\-\/\.](?<day>\d{1,2})/
        r.year=   m["year"].to_i
        r.month=  m["month"].to_i
        r.day=    m["day"].to_i
        r.update!
        ret= true
      end

      if m= date.match /(?<hour>\d{1,2}):(?<minute>\d{1,2}):(?<second>\d{1,2})(?:\.(?<millisecond>\d{1,6}))?/
        r.hour=   m["hour"].to_i
        r.minute= m["minute"].to_i
        r.second= m["second"].to_i
        r.millisecond= m["millisecond"].to_i if m["millisecond"]?
        ret= true
      end

      #def find_any(items, str)
      #  r = Regex.new(items.map(&->Regex.escape(String)).join('|'))
      #  str.scan(r) do |m|
      #    return m[0]
      #  end
      #end
      #p find_any({"one", "two", "three"}, "adfgagtwowafg")

      date= date.upcase
      if date=~ /\b(\d{4})\b/;  r.year= $1.to_i; r.update! end
      if v= Helpers.find_day_of_week( date); (r.day_of_week= Helpers::W2I[v]?) &&( ret= true) end
      if v= Helpers.find_month( date);       (r.month= Helpers::M2I[v]?) &&( ret= true); r.update! end
      unless ret
        if m= date.match /(?<day>\-?\d{1,2})/
          r.day= m["day"].to_i
          r.update!
          ret= true
        end
      end
      raise Crystime::Errors.incorrect_input unless ret
      r
    end

    # Checks if any element in list matches self.
    def matches?( list : Array, default= true)
      Crystime::Helpers.matches?( self, list, default)
    end
    def matches?( t : Crystime::VirtualTime | Time, default= true)
      Crystime::Helpers.matches?( self, [t], default)
    end

  end

  class Span
    protected getter span

    include Comparable(self)

    def initialize(d,h,m,s,ns)
      @span= Time::Span.new(d,h,m,s,ns)
      #after_initialize
    end
    def initialize(d,h,m,s)
      @span= Time::Span.new(d,h,m,s)
      #after_initialize
    end
    def initialize(h,m,s)
      @span= Time::Span.new(h,m,s)
      #fter_initialize
    end
    def initialize( seconds, nanoseconds = 0)
      @span= Time::Span.new(
        seconds: seconds,
        nanoseconds: nanoseconds,
      )
      #after_initialize
    end

    def total_seconds()
      @span.total_seconds
    end
    def total_milliseconds()
      @span.total_milliseconds
    end
    def total_nanoseconds()
      @span.total_nanoseconds
    end
    def nanoseconds()
      @span.nanoseconds
    end

    # XXX Since on the underlying level we're working with two Time::Spans,
    # can't we just use their +/- methods? (Assuming we're materialized,
    # of course)
    def +( other : self)
      Crystime::Span.new(
        seconds: span.to_i + other.span.to_i,
        nanoseconds: span.nanoseconds + other.span.nanoseconds,
      )
    end
    def -( other : self)
      Crystime::Span.new(
        seconds: span.to_i - other.span.to_i,
        nanoseconds: span.nanoseconds - other.span.nanoseconds,
      )
    end

    def <=>( other : self)
      total_nanoseconds<=> other.total_nanoseconds
    end

    #def days=( v, update?= true)         @days= v;         @ts[0]= v.is_a?( Int) ? true : false; update if update? end
    #def hours=( v, update?= true)        @hours= v;        @ts[1]= v.is_a?( Int) ? true : false; update if update? end
    #def seconds=( v, update?= true)      @seconds= v;      @ts[3]= v.is_a?( Int) ? true : false; update if update? end
    #def minutes=( v, update?= true)      @minutes= v;      @ts[2]= v.is_a?( Int) ? true : false; update if update? end
    #def milliseconds=( v, update?= true) @millisecond = v; @ts[4]= v.is_a?( Int) ? true : false; update if update? end
    #def update
    #end
  end

  # A custom to/from YAML converter for VirtualTime.
  class VirtualTimeConverter
    # Converts VirtualTime object to YAML.
    # XXX this has to be changed so that the whole object is serialized into yyyy/mm/dd/day_of_week hh:mm:ss.ms, not each field individually.
    def self.to_yaml(value : Crystime::VirtualTime::Virtual, yaml : YAML::Builder)
      case value
      #when Nil
      #  yaml.scalar "nil"
      when Int
        yaml.scalar value
      when Bool
        yaml.scalar value
      # This case wont match
      when Range(Int32,Int32)
        yaml.scalar value #.begin.to_s+ ".."+ (value.exclusive? ? value.end- 1 : value.end).to_s
      when Enumerable
        # The IF is here to workaround a bug in Crystal <= 0.23:
        # https://github.com/crystal-lang/crystal/issues/4684
        if value.class== Range(Int32,Int32)
          value= value.unsafe_as Range(Int32,Int32)
          yaml.scalar value #.begin.to_s+ ".."+ (value.exclusive? ? value.end- 1 : value.end).to_s
        else
          # Done in this way because in Crystal <= 0.23 there is
          # no way to detect a step once it's set:
          # https://github.com/crystal-lang/crystal/issues/4695
          yaml.scalar value.join ","
        end
      else
        raise "Unknown type #{value.class}"
      end
    end
    # Converts YAML to VirtualTime object.
   def self.from_yaml(value : YAML::PullParser) : Crystime::VirtualTime::Virtual
      v= value.read_scalar
      case v
      when "nil"
        nil
      when /^\d+$/
        v.to_i
      when /^(\d+)\.\.\.(\d+)(?:\/(\d+))$/
        ( $1.to_i...$2.to_i).step( $3.to_i)
      when /^(\d+)\.\.\.(\d+)$/
        $1.to_i...$2.to_i
      when /^(\d+)\.\.(\d+)(?:\/(\d+))$/
        ( $1.to_i..$2.to_i).step( $3.to_i)
      when /^(\d+)\.\.(\d+)$/
        $1.to_i..$2.to_i
      when "true"
        true
      when "false"
        false
      # XXX The next one is here just to satisfy return type. It doesn't really work.
      when /^->/
        ->( v : Int32){ true}
      else
        raise Crystime::Errors.invalid_yaml_input
      end
    end
  end
end

# TODO these formats should be supported by our parse:
#
#    assert_equal(Time.local( 2001,11,29,21,12), Time.parse("2001/11/29 21:12", now))
#    assert_equal(Time.local( 2001,11,29), Time.parse("2001/11/29", now))
#    assert_equal(Time.local( 2001,11,29), Time.parse(     "11/29", now))
#    #assert_equal(Time.local(2001,11,1), Time.parse("Nov", now))
#    assert_equal(Time.local( 2001,11,29,10,22), Time.parse(           "10:22", now))
#    now = Time.new(2001,2,3,0,0,0,"+09:00") # 2001-02-02 15:00:00 UTC
#    t = Time.parse("10:20:30 GMT", now)
#    assert_equal(true, Time.parse("2000-01-01T00:00:00Z").utc?)
#    assert_equal(true, Time.parse("2000-01-01T00:00:00-00:00").utc?)
#    assert_equal(false, Time.parse("2000-01-01T00:00:00+00:00").utc?)
#    assert_equal(false, Time.parse("Sat, 01 Jan 2000 00:00:00 GMT").utc?)
#    assert_equal(true, Time.parse("Sat, 01 Jan 2000 00:00:00 -0000").utc?)
#    assert_equal(false, Time.parse("Sat, 01 Jan 2000 00:00:00 +0000").utc?)
#    assert_equal(Time.new(2000,1,1,0,0,0,"+11:00"), Time.parse("2000-01-01T00:00:00+11:00", nil))
#    t = Time.utc(1998,12,31,23,59,59)
#    assert_equal(t, Time.parse("Thu Dec 31 23:59:59 UTC 1998"))
#    assert_equal(t, Time.parse("Fri Dec 31 23:59:59 -0000 1998"));t.localtime
#    assert_equal(t, Time.parse("Fri Jan  1 08:59:59 +0900 1999"))
#    assert_equal(t, Time.parse("Fri Jan  1 00:59:59 +0100 1999"))
#    assert_equal(t, Time.parse("Fri Dec 31 23:59:59 +0000 1998"))
#    assert_equal(t, Time.parse("Fri Dec 31 22:59:59 -0100 1998"));t.utc
#    t += 1
#    assert_equal(t, Time.parse("Thu Dec 31 23:59:60 UTC 1998"))
#    assert_equal(t, Time.parse("Fri Dec 31 23:59:60 -0000 1998"));t.localtime
#    assert_equal(t, Time.parse("Fri Jan  1 08:59:60 +0900 1999"))
#    assert_equal(t, Time.parse("Fri Jan  1 00:59:60 +0100 1999"))
#    assert_equal(t, Time.parse("Fri Dec 31 23:59:60 +0000 1998"))
#    assert_equal(t, Time.parse("Fri Dec 31 22:59:60 -0100 1998"));t.utc
#    t += 1 if t.sec == 60
#    assert_equal(t, Time.parse("Thu Jan  1 00:00:00 UTC 1999"))
#    assert_equal(t, Time.parse("Fri Jan  1 00:00:00 -0000 1999"));t.localtime
#    assert_equal(t, Time.parse("Fri Jan  1 09:00:00 +0900 1999"))
#    assert_equal(t, Time.parse("Fri Jan  1 01:00:00 +0100 1999"))
#    assert_equal(t, Time.parse("Fri Jan  1 00:00:00 +0000 1999"))
#    assert_equal(t, Time.parse("Fri Dec 31 23:00:00 -0100 1998"))
#    assert_equal(500000, Time.parse("2000-01-01T00:00:00.5+00:00").tv_usec)
#    assert_equal(123456789, Time.parse("2000-01-01T00:00:00.123456789+00:00").tv_nsec)
#    h = Date._parse('22:45:59.5')
#    assert_equal([22, 45, 59, 5.to_r/10**1], h.values_at(:hour, :min, :sec, :sec_fraction))
#    h = Date._parse('22:45:59.05')
#    assert_equal([22, 45, 59, 5.to_r/10**2], h.values_at(:hour, :min, :sec, :sec_fraction))
#    h = Date._parse('22:45:59.005')
#    assert_equal([22, 45, 59, 5.to_r/10**3], h.values_at(:hour, :min, :sec, :sec_fraction))
#    h = Date._parse('22:45:59.0123')
#    assert_equal([22, 45, 59, 123.to_r/10**4], h.values_at(:hour, :min, :sec, :sec_fraction))
#
#    h = Date._parse('224559.5')
#    assert_equal([22, 45, 59, 5.to_r/10**1], h.values_at(:hour, :min, :sec, :sec_fraction))
#    h = Date._parse('224559.05')
#    assert_equal([22, 45, 59, 5.to_r/10**2], h.values_at(:hour, :min, :sec, :sec_fraction))
#    h = Date._parse('224559.005')
#    assert_equal([22, 45, 59, 5.to_r/10**3], h.values_at(:hour, :min, :sec, :sec_fraction))
#    h = Date._parse('224559.0123')
#    assert_equal([22, 45, 59, 123.to_r/10**4], h.values_at(:hour, :min, :sec, :sec_fraction))
#
#    h = Date._parse('2006-w15-5')
#    assert_equal([2006, 15, 5], h.values_at(:cwyear, :cweek, :cwday))
#    h = Date._parse('2006w155')
#    assert_equal([2006, 15, 5], h.values_at(:cwyear, :cweek, :cwday))
#    h = Date._parse('06w155', false)
#    assert_equal([6, 15, 5], h.values_at(:cwyear, :cweek, :cwday))
#    h = Date._parse('06w155', true)
#    assert_equal([2006, 15, 5], h.values_at(:cwyear, :cweek, :cwday))
#
#    h = Date._parse('2006-w15')
#    assert_equal([2006, 15, nil], h.values_at(:cwyear, :cweek, :cwday))
#    h = Date._parse('2006w15')
#    assert_equal([2006, 15, nil], h.values_at(:cwyear, :cweek, :cwday))
#
#    h = Date._parse('-w15-5')
#    assert_equal([nil, 15, 5], h.values_at(:cwyear, :cweek, :cwday))
#    h = Date._parse('-w155')
#    assert_equal([nil, 15, 5], h.values_at(:cwyear, :cweek, :cwday))
#
#    h = Date._parse('-w15')
#    assert_equal([nil, 15, nil], h.values_at(:cwyear, :cweek, :cwday))
#    h = Date._parse('-w15')
#    assert_equal([nil, 15, nil], h.values_at(:cwyear, :cweek, :cwday))
#
#    h = Date._parse('-w-5')
#    assert_equal([nil, nil, 5], h.values_at(:cwyear, :cweek, :cwday))
#
#    h = Date._parse('--11-29')
#    assert_equal([nil, 11, 29], h.values_at(:year, :mon, :mday))
#    h = Date._parse('--1129')
#    assert_equal([nil, 11, 29], h.values_at(:year, :mon, :mday))
#    h = Date._parse('--11')
#    assert_equal([nil, 11, nil], h.values_at(:year, :mon, :mday))
#    h = Date._parse('---29')
#    assert_equal([nil, nil, 29], h.values_at(:year, :mon, :mday))
#    h = Date._parse('-333')
#    assert_equal([nil, 333], h.values_at(:year, :yday))
#
#    h = Date._parse('2006-333')
#    assert_equal([2006, 333], h.values_at(:year, :yday))
#    h = Date._parse('2006333')
#    assert_equal([2006, 333], h.values_at(:year, :yday))
#    h = Date._parse('06333', false)
#    assert_equal([6, 333], h.values_at(:year, :yday))
#    h = Date._parse('06333', true)
#    assert_equal([2006, 333], h.values_at(:year, :yday))
#    h = Date._parse('333')
#    assert_equal([nil, 333], h.values_at(:year, :yday))
#
#    h = Date._parse('')
#    assert_equal({}, h)
#  end
#
#    assert_equal(Date.new, Date.parse)
#    assert_equal(Date.new(2002,3,14), Date.parse('2002-03-14'))
#
#    assert_equal(DateTime.new(2002,3,14,11,22,33, 0), DateTime.parse('2002-03-14T11:22:33Z'))
#    assert_equal(DateTime.new(2002,3,14,11,22,33, 9.to_r/24), DateTime.parse('2002-03-14T11:22:33+09:00'))
#    assert_equal(DateTime.new(2002,3,14,11,22,33, -9.to_r/24), DateTime.parse('2002-03-14T11:22:33-09:00'))
#    assert_equal(DateTime.new(2002,3,14,11,22,33, -9.to_r/24) + 123456789.to_r/1000000000/86400, DateTime.parse('2002-03-14T11:22:33.123456789-09:00'))
#    d1 = DateTime.parse('2004-03-13T22:45:59.5')
#    d2 = DateTime.parse('2004-03-13T22:45:59')
#    assert_equal(d2 + 5.to_r/10**1/86400, d1)
#    d1 = DateTime.parse('2004-03-13T22:45:59.05')
#    d2 = DateTime.parse('2004-03-13T22:45:59')
#    assert_equal(d2 + 5.to_r/10**2/86400, d1)
#    d1 = DateTime.parse('2004-03-13T22:45:59.005')
#    d2 = DateTime.parse('2004-03-13T22:45:59')
#    assert_equal(d2 + 5.to_r/10**3/86400, d1)
#    d1 = DateTime.parse('2004-03-13T22:45:59.0123')
#    d2 = DateTime.parse('2004-03-13T22:45:59')
#    assert_equal(d2 + 123.to_r/10**4/86400, d1)
#    d1 = DateTime.parse('2004-03-13T22:45:59.5')
#    d1 += 1.to_r/2/86400
#    d2 = DateTime.parse('2004-03-13T22:46:00')
#    assert_equal(d2, d1)
#    n = DateTime.now
#
#    d = DateTime.parse('073')
#    assert_equal([n.year, 73, 0, 0, 0], [d.year, d.yday, d.hour, d.min, d.sec])
#    d = DateTime.parse('13')
#    assert_equal([n.year, n.mon, 13, 0, 0, 0], [d.year, d.mon, d.mday, d.hour, d.min, d.sec])
#
#    d = DateTime.parse('Mar 13')
#    assert_equal([n.year, 3, 13, 0, 0, 0], [d.year, d.mon, d.mday, d.hour, d.min, d.sec])
#    d = DateTime.parse('Mar 2004')
#    assert_equal([2004, 3, 1, 0, 0, 0], [d.year, d.mon, d.mday, d.hour, d.min, d.sec])
#    d = DateTime.parse('23:55')
#    assert_equal([n.year, n.mon, n.mday, 23, 55, 0], [d.year, d.mon, d.mday, d.hour, d.min, d.sec])
#    d = DateTime.parse('23:55:30')
#    assert_equal([n.year, n.mon, n.mday, 23, 55, 30], [d.year, d.mon, d.mday, d.hour, d.min, d.sec])
#
#    d = DateTime.parse('Sun 23:55')
#    d2 = d - d.wday
#    assert_equal([d2.year, d2.mon, d2.mday, 23, 55, 0],
#    [d.year, d.mon, d.mday, d.hour, d.min, d.sec])
#    d = DateTime.parse('Aug 23:55')
#    assert_equal([n.year, 8, 1, 23, 55, 0],
#    [d.year, d.mon, d.mday, d.hour, d.min, d.sec])
#
#    d = Date.new(2002,3,14)
#    assert_equal(d, Date.parse(d.to_s))
#
#    d = DateTime.new(2002,3,14,11,22,33, 9.to_r/24)
#    assert_equal(d, DateTime.parse(d.to_s))
