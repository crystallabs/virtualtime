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
    @ts= [ nil, nil,  nil,  nil,  nil,  nil,  nil] of Bool?

    # Empty constructor. Must be here since when fields are defined, the
    # default empty constructor is not created.
    def initialize
    end

    def year=( v)        @year= v;   @ts[0]= v.is_a?( Int) ? true : v.nil? ? nil : false; update! end
    def month=( v)       @month= v;  @ts[1]= v.is_a?( Int) ? true : v.nil? ? nil : false; update! end
    def day=( v)         @day= v;    @ts[2]= v.is_a?( Int) ? true : v.nil? ? nil : false; update! end
    def hour=( v)        @hour= v;   @ts[3]= v.is_a?( Int) ? true : v.nil? ? nil : false; update! end
    def minute=( v)      @minute= v; @ts[4]= v.is_a?( Int) ? true : v.nil? ? nil : false; update! end
    def second=( v)      @second= v; @ts[5]= v.is_a?( Int) ? true : v.nil? ? nil : false; update! end
    def millisecond=( v) @millisecond= v; @ts[6]= v.is_a?( Int) ? true : v.nil? ? nil : false; update! end
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
      if date=~ /\b(\d{4})\b/;  r.year= $1.to_i end
      if v= find_weekday( date); r.day= W2I[v]? &&( ret= true) end
      if v= find_month( date); r.month= M2I[v]? &&( ret= true) end
      unless ret
        if m= date.match /(?<day>\-?\d{1,2})/
          r.day=   m["day"].to_i
          ret= true
        end
      end
      raise Crystime::Errors.incorrect_input unless ret
      r.update!
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
		#	raise Crystime::Errors.virtual_comparison if @ts.any?{ |x| x== false}
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
    def abs() @span.ticks.abs end
    def to_f() @span.to_f end
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
      # TODO this code prevents to perfectly simple/comparable VDs from being compared (at least for literal ==)
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

  end
