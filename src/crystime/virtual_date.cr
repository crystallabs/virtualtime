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
    end
		end
