# VirtualDate is a flexible representation of a date, allowing
# it to be full, partial, contain ranges, procs, etc.
# It also offers out of the box support for comparing and
# matching VirtualDates.

require "yaml"

module Crystime
  class VirtualDate
    W2I= { "SUN" => 0, "MON" => 1, "TUE" => 2, "WED" => 3, "THU" => 4, "FRI" => 5, "SAT" => 6}
    I2W= W2I.invert
    WR=  Regex.new "\\b("+ W2I.keys.map(&->Regex.escape(String)).join('|')+ ")\\b"

    M2I= { "JAN" => 1, "FEB" => 2, "MAR" => 3, "APR" => 4, "MAY" => 5, "JUN" => 6, "JUL" => 7, "AUG" => 8, "SEP" => 9, "OCT" => 10, "NOV" => 11, "DEC" => 12}
    I2M= M2I.invert
    MR=  Regex.new "\\b("+ M2I.keys.map(&->Regex.escape(String)).join('|')+ ")\\b"

    include Comparable(self)

    #property :relative
    protected getter :time
    property :ts

    # XXX need to move to model where user input is separate from actual values.
    # E.g. day should be able to be -1, but for calcs it needs to be last day in month.
    # And until we know year and month, we can't fill in weekday/jd, nor evaluate that -1.
    # But while treated as object or in yaml, it needs to be -1, not actual value.
    # Weekday, jd and date -X require dates to be materialized...

    # XXX Use Int instead of Int32 when it becomes possible in Crystal
    alias Virtual = Nil | Int32 | Bool | Range(Int32, Int32) | Enumerable(Int32) | Proc(Int32, Bool)

    YAML.mapping({
      # Date-related properties
      month:       { type: Virtual, nilable: true, setter: false, converter: Crystime::VirtualDateConverter},
      year:        { type: Virtual, nilable: true, setter: false, converter: Crystime::VirtualDateConverter},
      day:         { type: Virtual, nilable: true, setter: false, converter: Crystime::VirtualDateConverter},
      weekday:     { type: Virtual, nilable: true, setter: false, converter: Crystime::VirtualDateConverter},
      jd:          { type: Virtual, nilable: true, setter: false, converter: Crystime::VirtualDateConverter},
      # Time-related properties
      hour:        { type: Virtual, nilable: true, setter: false, converter: Crystime::VirtualDateConverter},
      minute:      { type: Virtual, nilable: true, setter: false, converter: Crystime::VirtualDateConverter},
      second:      { type: Virtual, nilable: true, setter: false, converter: Crystime::VirtualDateConverter},
      millisecond: { type: Virtual, nilable: true, setter: false, converter: Crystime::VirtualDateConverter},
    })

    #@relative: Nil | Bool

    # "ts" is a variable which keeps track of which fields were actually specified in VirtualDate.
    # E.g., if a user specifically sets seconds value (even if 0), then field 5 will be true. Otherwise, it will be false.
    # This is important for matching VirtualDates, because if one VirtualDate has ts[5] set to nil (not specified), and
    # the other has ts[5] set to true, that will be considered a match. (An unspecified value matches all possible values.)
    #      0    1     2     3     4     5     6
    #      year month day   hour  min   sec   ms
    getter ts : Array(Bool?)
    @ts= [ nil, nil,  nil,  nil,  nil,  nil,  nil] of Bool?

    # Empty constructor. Must be here since when fields are defined, the
    # default empty constructor is not created.
    def initialize
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
    def weekday=( v)
      @weekday= v
      true
    end
    # Julian Day Number does affect actual date, but is not used in calculations.
    def jd=( v)
      from_jd! if @jd= v
      true
    end
    def from_jd!
      raise Crystime::Errors.invalid_jd unless jd= from_jd
      @year, @month, @day= jd[0], jd[1], jd[2]
      true
    end

    # Called when year, month, or day are re-set and we need to re-calculate which weekday and
    # Julian Day Number the new date corresponds to. This is only filled if y/m/d is specified.
    # If it is not specified (meaning that the VirtualDate does not refer to a specific date),
    # then they are set to nil.
    def update!
      if @ts[0]&& @ts[1]&& @ts[2]
        #puts "date is: "+ self.inspect
        t= Time.new(@year.as( Int), @month.as( Int), @day.as( Int), kind: Time::Kind::Utc)
        @weekday= t.day_of_week.to_i
        @jd= to_jd!
      else
        @weekday= @jd= nil
      end
      true
    end

    # Expand a partial VirtualDate into a materialized/specific date/time.
    def expand
      [@year, @month, @day, @hour, @minute, @second, @millisecond].expand.map{ |v| Crystime::VirtualDate.from_array v}
    end

    # Creates VirtualDate from Julian Day Number.
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
    # Creates Julian Day Number from VirtualDate, when possible. Raises otherwise.
    def to_jd!
      if @ts[0]&& @ts[1]&& @ts[2]
        a= ((14-@month.as( Int))/12).floor
        y= @year.as( Int)+ 4800- a
        m= @month.as( Int)+ 12*a- 3
        @day.as( Int)+ ((153*m+ 2)/5).floor+ 365*y+ (y/4).floor- (y/100).floor+ (y/400).floor- 32045
      else
        raise "Can't convert non-specific date to Julian Day Number"
      end
    end

    def <=>( other : self)
      #p "<=>"
      to_time<=>other.to_time
    end
    def +( other : Span)
      self_time= self.to_time
      t= Time.epoch(0) + Time::Span.new(
        seconds: (self_time.epoch+ other.total_seconds).floor.to_i64,
        nanoseconds: (self_time.nanosecond+ other.nanoseconds).floor.to_i32,
      )
      if (t.year        != 0)                     ; self.year= t.year               end
      if (t.month       != 0)                     ; self.month= t.month             end
      if (t.day         != 0) || !other.ts[0].nil?; self.day= t.day                 end
      if (t.hour        != 0) || !other.ts[1].nil?; self.hour= t.hour               end
      if (t.minute      != 0) || !other.ts[2].nil?; self.minute= t.minute           end
      if (t.second      != 0) || !other.ts[3].nil?; self.second= t.second           end
      if (t.millisecond != 0) || !other.ts[4].nil?; self.millisecond= t.millisecond end
      self
    end
    # XXX add tests for @ts=[...] looking correct after VirtualDate+ Span
    def -( other : Span) self+ -other end
    def +( other : self)
      self_time= self.to_time
      other_time= other.to_time
      Span.new(
        seconds: (self_time.epoch+ other_time.epoch).floor,
        nanoseconds: (self_time.nanosecond+ other_time.nanosecond).floor
      )
    end
    def -( other : self)
      self_time= self.to_time
      other_time= other.to_time
      Span.new(
        seconds: (self_time.epoch- other_time.epoch).floor,
        nanoseconds: (self_time.nanosecond- other_time.nanosecond).floor
      )
    end

    def to_time
      # XXX ability to define default values for nils
      #p "in ticks: "+ @ts.inspect
      if @ts.any?{ |x| x== false}
        # XXX not comparison but inability to materialize
        raise Crystime::Errors.virtual_comparison
      end
      ms, sec, min, h, d, m, y= @millisecond, @second, @minute, @hour, @day, @month, @year
      ms= ms.nil?   ? 0 : ms.as( Int)
      sec= sec.nil? ? 0 : sec.as( Int)
      min= min.nil? ? 0 : min.as( Int)
      h= h.nil?     ? 0 : h.as( Int)
      d= d.nil?     ? 1 : d.as( Int)
      m= m.nil?     ? 1 : m.as( Int)
      y= y.nil?     ? 1 : y.as( Int)
      Time.new( y, m, d, hour: h, minute: min, second: sec, nanosecond: ms* 1_000_000, kind: Time::Kind::Utc)
    end

    def self.from_array( arg)
      r= new
      r.year= arg[0]
      r.month= arg[1]
      r.day= arg[2]
      r.hour= arg[3]
      r.minute= arg[4]
      r.second= arg[5]
      r.millisecond= arg[6]
      r
    end

    def utc?() true end

    def materialized?
      #@ts[0..2]= [true,true,true]
      @ts.all?{ |x| x== true}
    end
    def materialize!
    # XXX this should work with the help of "other" date; if one
    # is not specified default time is used.
      #t= Time.now
      # XXX modify so that if value is proc, we call it;
      # if value is range, we take range.begin,
      # if value is 
      # It's OK to use these values here because if a person does not
      # want to materialize to these probably-not-useful values,
      # they simply need to provide 'other' as argument.
      # XXX but do solve the case of field== false. Right now we override
      # those with these default values, which is incorrect. (E.g. a 
      # range needs to materialize to range.begin, not to 1 or 0).
      self.year        ||= 1
      self.month       ||= 1
      self.day         ||= 1
      # XXX use some configurable defaults?
      self.hour        ||= 0
      self.minute      ||= 0
      self.second      ||= 0
      self.millisecond ||= 0
    end
    # Replace with macro and fix logic
    def merge( other : self)
      self.year        ||= other.year
      self.month       ||= other.month
      self.day         ||= other.day
      # XXX ditto
      self.hour        ||= other.hour
      self.minute      ||= other.minute
      self.second      ||= other.second
      self.millisecond ||= other.millisecond
    end

    def to_tuple
      { @year, @month, @day, @weekday, @jd, @hour, @minute, @second, @millisecond}
    end

    # Parses string and produces VirtualDate.
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
      if v= find_weekday( date); (r.weekday= W2I[v]?) &&( ret= true) end
      if v= find_month( date);     (r.month= M2I[v]?) &&( ret= true); r.update! end
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

    private def self.find_weekday( str)
      str.scan(WR) do |m| return m[0] end
      nil
    end
    private def self.find_month( str)
      str.scan(MR) do |m| return m[0] end
      nil
    end

  end

  class Span
    getter :ts

    #      0   1   2   3   4
    #      d   h   m   s   ms
    @ts= [ nil,nil,nil,nil,nil] of Bool?

    include Comparable(self)

    def initialize(d,h,m,s,ms)
      @span= Time::Span.new(d,h,m,s,ms* 1_000_000)
      @ts[0..4]= [true,true,true,true,true]
      #after_initialize
    end
    def initialize(d,h,m,s)
      @span= Time::Span.new(d,h,m,s)
      @ts[0..3]= [true,true,true,true]
      #after_initialize
    end
    def initialize(h,m,s)
      @span= Time::Span.new(h,m,s)
      @ts[1..3]= [true,true,true]
      #fter_initialize
    end
    #def initialize(ticks)
    #  @span= Time::Span.new(ticks)
    #  #after_initialize
    #end
    def initialize( seconds, nanoseconds)
      @span= Time::Span.new(
        seconds: seconds,
        nanoseconds: nanoseconds,
      )
      #after_initialize
    end

    #def after_initialize
    #  s= @span
    #  raise "Missing Time::Span!" unless s
    #  @ticks= s.ticks
    #end

    #def ticks()
    # raise Crystime::Errors.virtual_comparison if @ts.any?{ |x| x== false}
    #  @span.ticks
    #end
    def total_seconds()
      raise Crystime::Errors.virtual_comparison if @ts.any?{ |x| x== false}
      @span.total_seconds
    end
    def total_milliseconds()
      raise Crystime::Errors.virtual_comparison if @ts.any?{ |x| x== false}
      @span.total_milliseconds
    end
    def total_nanoseconds()
      raise Crystime::Errors.virtual_comparison if @ts.any?{ |x| x== false}
      @span.total_nanoseconds
    end
    def nanoseconds()
      raise Crystime::Errors.virtual_comparison if @ts.any?{ |x| x== false}
      @span.nanoseconds
    end

    # XXX ticks doesn't work >= crystal 0.24.1 and this needs fixing?
    def abs() @span.ticks.abs end

    def to_f() @span.to_f end

    # XXX Since on the underlying level we're working with two Time::Spans,
    # can't we just use their +/- methods? (Assuming we're materialized,
    # of course)
    def +( other : self)
      Span.new(
        seconds: (total_seconds+ other.total_seconds).floor.to_i64,
        nanoseconds: (nanoseconds+ other.nanoseconds).floor.to_i32,
      )
    end
    def -( other : self)
      Span.new(
        seconds: (total_seconds- other.total_seconds).floor.to_i64,
        nanoseconds: (nanoseconds- other.nanoseconds).floor.to_i32,
      )
    end

    def <=>( other : self)
      # TODO this code prevents two perfectly simple/comparable VDs from being compared (at least for literal ==)
      #return {@year, @month, @day, @weekday, @jd, @hour, @minute, @second, @millisecond} <=> {other.year, other.month, other.day, other.weekday, other.jd, other.hour, other.minute, other.second, other.millisecond}
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

  # A custom to/from YAML converter for VirtualDate.
  class VirtualDateConverter
    # Converts VirtualDate object to YAML.
    # XXX this has to be changed so that the whole object is serialized into yyyy/mm/dd/weekday hh:mm:ss.ms, not each field individually.
    def self.to_yaml(value : Crystime::VirtualDate::Virtual, yaml : YAML::Builder)
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
    # Converts YAML to VirtualDate object.
   def self.from_yaml(value : YAML::PullParser) : Crystime::VirtualDate::Virtual
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
