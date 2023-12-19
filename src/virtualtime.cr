require "yaml"

class Steppable::StepIterator(T, L, B)
  getter current, limit, step, exclusive
end

class VirtualTime
  VERSION_MAJOR    = 1
  VERSION_MINOR    = 1
  VERSION_REVISION = 4
  VERSION          = [VERSION_MAJOR, VERSION_MINOR, VERSION_REVISION].join '.'

  include Comparable(Time)
  include YAML::Serializable

  # TODO Use Int instead of Int32 when it becomes possible in unions in Crystal
  # Separately, XXX, https://github.com/crystal-lang/crystal/issues/14047, when it gets solved, add Enumerable(Int32) and remove Array/Steppable
  alias Virtual = Nil | Bool | Int32 | Array(Int32) | Range(Int32, Int32) | Steppable::StepIterator(Int32, Int32, Int32) | VirtualProc
  alias VirtualProc = Proc(Int32, Bool)
  alias VTTuple = Tuple(Virtual, Virtual, Virtual, Virtual, Virtual, Virtual, Virtual, Virtual, Virtual, Virtual, Virtual, Time::Location?)
  alias TimeOrVirtualTime = Time | self

  # Date-related properties

  @[YAML::Field(converter: VirtualTime::VirtualConverter)]
  property year : Virtual # 1

  @[YAML::Field(converter: VirtualTime::VirtualConverter)]
  property month : Virtual # 1

  @[YAML::Field(converter: VirtualTime::VirtualConverter)]
  property day : Virtual # 1

  # Higher-level date-related properties

  @[YAML::Field(converter: VirtualTime::VirtualConverter)]
  property week : Virtual # 1

  @[YAML::Field(converter: VirtualTime::VirtualConverter)]
  property day_of_week : Virtual # 1 - Monday

  @[YAML::Field(converter: VirtualTime::VirtualConverter)]
  property day_of_year : Virtual # 1

  # Time-related properties

  @[YAML::Field(converter: VirtualTime::VirtualConverter)]
  property hour : Virtual # 0

  @[YAML::Field(converter: VirtualTime::VirtualConverter)]
  property minute : Virtual # 0

  @[YAML::Field(converter: VirtualTime::VirtualConverter)]
  property second : Virtual # 0

  @[YAML::Field(converter: VirtualTime::VirtualConverter)]
  property millisecond : Virtual # 0

  @[YAML::Field(converter: VirtualTime::VirtualConverter)]
  property nanosecond : Virtual # 0

  # Location/timezone in which to perform matching, if any
  @[YAML::Field(converter: VirtualTime::TimeLocationConverter)]
  property location : Time::Location?

  # Default match result if one of field values matched is `nil`
  class_property? default_match : Bool = true

  def initialize(@year = nil, @month = nil, @day = nil, @hour = nil, @minute = nil, @second = nil, *, @millisecond = nil, @nanosecond = nil, @day_of_week = nil, @day_of_year = nil, @week = nil)
  end

  def initialize(*, @year, @week, @day_of_week = nil, @hour = nil, @minute = nil, @second = nil, @millisecond = nil, @nanosecond = nil)
  end

  def initialize(@year, @month, @day, @week, @day_of_week, @day_of_year, @hour, @minute, @second, @millisecond, @nanosecond, @location)
  end

  # Matching

  # :nodoc:
  macro adjust_location
    if time.is_a? Time
      if (l = location) && (time.location != l)
        time = time.in l
      end
    else
      if location != time.location
        raise ArgumentError.new "Comparing VirtualTimes with different locations/timezones not supported (yet?)"
      end
    end
  end

  # Returns whether `VirtualTime` matches the specified time
  def matches?(time : TimeOrVirtualTime = Time.local)
    adjust_location
    matches_date?(time) && matches_time?(time)
  end

  # :ditto:
  #
  # Alias for `matches?`.
  @[AlwaysInline]
  def ==(time : TimeOrVirtualTime = Time.local)
    matches? time
  end

  # Returns whether `VirtualTime` matches the date part of specified time
  def matches_date?(time : TimeOrVirtualTime = Time.local)
    adjust_location
    self.class.matches?(year, time.year, 9999) &&
      self.class.matches?(month, time.month, 12) &&
      self.class.matches?(day, time.day, TimeHelper.days_in_month(time)) &&
      self.class.matches?(week, TimeHelper.week(time), TimeHelper.weeks_in_year(time)) &&
      self.class.matches?(day_of_week, TimeHelper.day_of_week(time), 7) &&
      self.class.matches?(day_of_year, TimeHelper.day_of_year(time), TimeHelper.days_in_year(time))
  end

  # Returns whether `VirtualTime` matches the time part of specified time
  def matches_time?(time : TimeOrVirtualTime = Time.local)
    adjust_location
    self.class.matches?(hour, time.hour, 23) &&
      self.class.matches?(minute, time.minute, 59) &&
      self.class.matches?(second, time.second, 59) &&
      self.class.matches?(millisecond, time.millisecond, 999) &&
      self.class.matches?(nanosecond, time.nanosecond, 999_999_999)
  end

  # Performs matching between VirtualTime and other supported types
  def self.matches?(a : Nil, b, max = nil)
    return false if b == false
    default_match?
  end

  # :ditto:
  def self.matches?(a : Bool, b, max = nil)
    return false if b == false
    a
  end

  # :ditto:
  def self.matches?(a : Int, b : Int, max = nil)
    if max
      a = max + a + 1 if a < 0
      b = max + b + 1 if b < 0
    end
    a == b
  end

  # # ###### Possibly enable
  # # :ditto:
  # def self.matches?(a : Array(Int), b : Int, max = nil)
  #   a.each do |aa|
  #     return true if matches? aa, b, max
  #   end
  #   false
  # end

  # # :ditto:
  # def self.matches?(a : Range(Int, Int), b : Int, max = nil)
  #   if max && (a.begin < 0 || a.end < 0)
  #     ab = a.begin < 0 ? max + a.begin + 1 : a.begin
  #     ae = a.end < 0 ? max + a.end + 1 : a.end
  #     a = ab..ae
  #   end
  #   a.each do |aa|
  #     return true if matches? aa, b, max
  #   end
  #   false
  # end

  # # :ditto:
  # def self.matches?(a : Steppable::StepIterator(Int, Int, Int), b : Int, max = nil)
  #   if max && (a.current < 0 || a.limit < 0)
  #     ab = a.current < 0 ? max + a.current + 1 : a.current
  #     ae = a.limit < 0 ? max + a.limit + 1 : a.limit
  #     a = Steppable::StepIterator(Int32, Int32, Int32).new ab, ae, a.step, a.exclusive
  #   else
  #     a = a.dup
  #   end
  #   a.each do |aa|
  #     return true if matches? aa, b, max
  #   end
  #   false
  # end

  # # ###### Possibly enable

  # :ditto:
  def self.matches?(a : Enumerable(Int), b : Int, max = nil)
    a.dup.each do |aa|
      return true if matches? aa, b, max
    end
    false
  end

  # # ###### Possibly enable
  # # :ditto:
  # def self.matches?(a : Array(Int), b : Array(Int), max = nil)
  #   a.each do |aa|
  #     b.each do |bb|
  #       return true if matches? aa, bb, max
  #     end
  #   end
  #   false
  # end

  # # :ditto:
  # def self.matches?(a : Range(Int, Int), b : Range(Int, Int), max = nil)
  #   if max
  #     if (a.begin < 0 || a.end < 0)
  #       ab = a.begin < 0 ? max + a.begin + 1 : a.begin
  #       ae = a.end < 0 ? max + a.end + 1 : a.end
  #       a = ab..ae
  #     end
  #     if (b.begin < 0 || b.end < 0)
  #       bb = b.begin < 0 ? max + b.begin + 1 : b.begin
  #       be = b.end < 0 ? max + b.end + 1 : b.end
  #       b = bb..be
  #     end
  #   end
  #   a.each do |aa|
  #     b.each do |bb|
  #       return true if matches? aa, bb, max
  #     end
  #   end
  #   false
  # end

  # # :ditto:
  # def self.matches?(a : Steppable::StepIterator(Int, Int, Int), b : Steppable::StepIterator(Int, Int, Int), max = nil)
  #   if max
  #     if a.current < 0 || a.limit < 0
  #       ab = a.current < 0 ? max + a.current + 1 : a.current
  #       ae = a.limit < 0 ? max + a.limit + 1 : a.limit
  #       a = Steppable::StepIterator(Int32, Int32, Int32).new ab, ae, a.step, a.exclusive
  #     else
  #       a = a.dup
  #     end
  #     if b.current < 0 || b.limit < 0
  #       bb = b.current < 0 ? max + b.current + 1 : b.current
  #       be = b.limit < 0 ? max + b.limit + 1 : b.limit
  #       b = Steppable::StepIterator(Int32, Int32, Int32).new bb, be, b.step, b.exclusive
  #     else
  #       b = b.dup
  #     end
  #   end
  #   a.each do |aa|
  #     b.each do |bb|
  #       return true if matches? aa, bb, max
  #     end
  #   end
  #   false
  # end

  # # ###### Possibly enable

  # :ditto:
  def self.matches?(a : Enumerable(Int), b : Enumerable(Int), max = nil)
    a.dup.each do |aa|
      b.dup.each do |bb|
        return true if matches? aa, bb, max
      end
    end
    false
  end

  # :ditto:
  def self.matches?(a : Enumerable(Int), b : VirtualProc, max = nil)
    a.dup.each do |aa|
      aa = max + aa + 1 if max && (aa < 0)
      return true if b.call aa
    end
    false
  end

  # :ditto:
  def self.matches?(a : VirtualProc, b : Int, max = nil)
    b = max + b + 1 if max && (b < 0)
    a.call b
  end

  # :ditto:
  def self.matches?(a : VirtualProc, b : VirtualProc, max = nil)
    raise ArgumentError.new "Proc to Proc comparison not supported (yet?)"
  end

  def self.matches?(a, b, max = nil)
    matches? b, a, max
  end

  # be Bool, Enumerable(Int), Int, Nil, Proc(Virtual, Bool) or Range(Int, Int)
  # no (Array(Int32) | | Proc(Virtual, Bool) | Range(Int32, Int32) | Steppable::StepIterator(Int32, Int32, Int32)

  # Materializing
  # Time: year, month, day, calendar_week, day_of_week, day_of_year, hour, minute, second, millisecond, nanosecond, location

  # Returns a new, "materialized" VirtualTime. I.e., it converts VirtualTime object to a Time-like value, where all fields have "materialized"/specific values
  def materialize(hint = Time.local, strict = true)
    # TODO Possibly default the hint to now + 1 minute, with second/nanosecond values set to 0
    self.class.new **materialize_with_hint(hint)
  end

  # :nodoc:
  def materialize_with_hint(time : Time)
    {
      year:       self.class.materialize(year, time.year, 9999),
      month:      self.class.materialize(month, time.month, 12),
      day:        self.class.materialize(day, time.day, TimeHelper.days_in_month(time)),
      hour:       self.class.materialize(hour, time.hour, 23),
      minute:     self.class.materialize(minute, time.minute, 59),
      second:     self.class.materialize(second, time.second, 59),
      nanosecond: self.class.materialize(nanosecond, time.nanosecond, 999_999_999),
    }
  end

  # Materialize a particular value with the help of a hint/default value.
  # If 'strict' is true and default value does not satisfy predefined range or requirements, the default is replaced with the first/earliest value from allowed range.
  def self.materialize(value : Nil, default : Int32, max = nil, strict = true)
    default
  end

  # :ditto:
  def self.materialize(value : Bool, default : Int32, max = nil, strict = true)
    default
  end

  # :ditto:
  def self.materialize(value : Int, default : Int32, max = nil, strict = true)
    max && (value < 0) ? max + value + 1 : value
  end

  # :ditto:
  def self.materialize(value : Enumerable(Int), default : Int32, max = nil, strict = true)
    if max && value.any?(&.<(0))
      value = value.map { |e| e < 0 ? max + e + 1 : e }
    end
    if !strict || value.includes? default
      default
    else
      value.min
    end
  end

  # :ditto:
  def self.materialize(value : Range(Int, Int), default : Int32, max = nil, strict = true)
    if max && (value.begin < 0 || value.end < 0)
      ab = value.begin < 0 ? max + value.begin + 1 : value.begin
      ae = value.end < 0 ? max + value.end + 1 : value.end
      value = ab..ae
    end

    if !strict || value.includes? default
      default
    else
      value.begin
    end
  end

  # :ditto:
  def self.materialize(value : Proc(Virtual, Bool), default : Int32, max = nil, strict = true)
    default
  end

  # Comparison with self

  def ==(other : self)
    (year == other.year) &&
      (month == other.month) &&
      (day == other.day) &&
      (week == other.week) &&
      (day_of_week == other.day_of_week) &&
      (day_of_year == other.day_of_year) &&
      (hour == other.hour) &&
      (minute == other.minute) &&
      (second == other.second) &&
      (millisecond == other.millisecond) &&
      (nanosecond == other.nanosecond)
  end

  # Comparison and conversion to and from time

  # Compares `VirtualTime` to `Time` instance
  def <=>(other : Time)
    to_time <=> other
  end

  # "Rewinds" `day` forward enough to reach `acceptable_day`.
  #
  # It wraps around `wrap_day`, so e.g. `adjust_day(25, 5, 30)` returns `10.days`
  def adjust_day(day : Int, acceptable_day : Int, wrap_day : Int)
    amount = 0

    if day != acceptable_day
      if acceptable_day > day
        amount = (acceptable_day - day)
      else
        amount = (wrap_day - day) + acceptable_day
      end
    end

    amount.days
  end

  # Converts a VirtualTime to a specific Time object that hopefully matches the VirtualTime.
  #
  # Value is converted using a time hint, which defaults to the current time.
  # Lists and ranges of values materialize to their min / begin value.
  #
  # Additionally, any requirements for week number, day of week, and day of year are also met,
  # possibly by doing multiple iterations to find a suitable date. The process is limited to
  # 10 attempts of trying to find a value that simultaneously satisfies all constraints.
  def to_time(hint = Time.local, strict = true)
    # TODO Possibly default the hint to now + 1 minute, with second/nanosecond values set to 0
    time = Time.local **materialize_with_hint(hint), location: hint.location

    max_tries = 10
    tries = 0
    loop do
      tries += 1

      week_nr = time.calendar_week[1]
      time += adjust_day(week_nr, self.class.materialize(week, week_nr, TimeHelper.weeks_in_year(time), strict), TimeHelper.weeks_in_year(time)) * 7

      day = time.day_of_week.to_i
      time += adjust_day(day, self.class.materialize(day_of_week, day, 7, strict), 7)

      day = time.day_of_year
      time += adjust_day(day, self.class.materialize(day_of_year, day, TimeHelper.days_in_year(time), strict), TimeHelper.days_in_year(time))

      if matches_date?(time)
        break
      else
        if tries >= max_tries
          # TODO maybe some other error, not arg err
          raise ArgumentError.new "Could not find a date that satisfies week number, day of week, and day of year after #{max_tries} iterations"
        end
      end
    end

    time
  end

  # Creates `VirtualTime` from `Time`.
  # This can be useful to produce a VT with many fields filled in quickly, and then set fields of choice to more interesting values rather than fixed integers.
  #
  # Note that this copies all values from `Time` to `VirtualTime`, including week number, day of week, day of year.
  # That results in a very fixed `VirtualTime` which is probably not useful unless some values are afterwards reset to nil or set to other VT-specific options.
  #
  # Millisecond and nanosecond values are copied from `Time` into `VirtualTime` only if options `milliseconds=` and `nanoseconds=` are set to true.
  # Default is currently true for nanoseconds.
  # Whether these options are useful, or whether they should be removed, or whether all fields should get a corresponding option like this, remains be seen.
  def self.from_time(time : Time, *, milliseconds = false, nanoseconds = true)
    new \
      year: time.year,
      month: time.month,
      day: time.day,
      week: time.calendar_week[1],
      day_of_week: time.day_of_week.to_i,
      day_of_year: time.day_of_year,
      hour: time.hour,
      minute: time.minute,
      second: time.second,
      millisecond: milliseconds ? time.millisecond : nil,
      nanosecond: nanoseconds ? time.nanosecond : nil
  end

  # Convenience functions

  def nil_date!
    self.year = nil
    self.month = nil
    self.day = nil
    self.week = nil
    self.day_of_week = nil
    self.day_of_year = nil
    self
  end

  def nil_time!
    self.hour = nil
    self.minute = nil
    self.second = nil
    self.millisecond = nil
    self.nanosecond = nil
    self.location = nil
    self
  end

  # Misc conversions

  # Outputs VirtualTime instance as a tuple with signature `Tuple(11x Virtual, Time::Location?)`
  def to_tuple
    VTTuple.new year, month, day, week, day_of_week, day_of_year, hour, minute, second, millisecond, nanosecond, location
  end

  # Expands VirtualTime containing ranges or lists into a list of individual VirtualTimes with specific values
  # E.g. VirtualTime with `day=1..2` gets expanded into two separate VirtualTimes, day=1 and day=2
  def expand
    ArrayHelper.expand(VTTuple.new year, month, day, week, day_of_week, day_of_year, hour, minute, second, millisecond, nanosecond, location).map { |v| self.class.new *(VTTuple.from v) }
  end

  # Helper methods below

  module TimeHelper
    # Returns number of weeks in a year.
    # It is calculated as number of Mondays in the year up to the ordinal date.
    #
    # Thus it is possible for this function to return value of `53` (53th week in a year) for up to 4 last days in the current year.
    # That is, for Dec 28-31. An example of such year was 2020.
    #
    # In other words, value `53` will be seen if January 1 of next year is on a Friday, or the year was a leap year.
    #
    # The calculation is identical as the first part of `Time#calendar_week`.
    # .
    def self.weeks_in_year(time : Time)
      (time.at_end_of_year.day_of_year - time.day_of_week.to_i + 10) // 7
    end

    def self.weeks_in_year(time : VirtualTime)
      0
    end

    # Returns current week of year.
    #
    # This function returns a value in range 0..53.
    #
    # Up to first 3 days of a year (Jan 1-3) may return value 0. This means they are in the new year, but technically they belong to a week that started on Monday in the previous year.
    # Week number 53 means January 1 is on a Friday, or the year was a leap year.
    #
    # The calculation is identical as the first part of `Time#calendar_week`.
    def self.week_of_year(time)
      (time.day_of_year - time.day_of_week.to_i + 10) // 7
    end

    # Returns number of days in current month
    def self.days_in_month(time : Time)
      Time.days_in_month time.year, time.month
    end

    def self.days_in_month(time : VirtualTime)
      nil
    end

    def self.week(time : Time)
      time.calendar_week[1].to_i
    end

    def self.week(time : VirtualTime)
      time.week
    end

    def self.day_of_week(time : Time)
      time.day_of_week.to_i
    end

    def self.day_of_week(time : VirtualTime)
      time.day_of_week
    end

    def self.day_of_year(time)
      time.day_of_year
    end

    # Returns number of days in current year
    def self.days_in_year(time : Time)
      Time.days_in_year time.year
    end

    def self.days_in_year(time : VirtualTime)
      nil
    end
  end

  module ArrayHelper
    # Expands ranges and other expandable types into a long list of all possible options.
    # E.g. [1, 2..3, 4..5] gets expanded into [[1, 2, 4], [1,2, 5], [1,3,4], [1,3,5]].
    def self.expand(list)
      Indexable.cartesian_product list.map { |e|
        case e
        when Array
          e
        when Enumerable
          e.dup.to_a
        else
          [e]
        end
      }
    end
  end

  # A custom to/from YAML converter for VirtualTime.
  class VirtualConverter
    def self.to_yaml(value : VirtualTime::Virtual, yaml : YAML::Nodes::Builder)
      case value
      # when Nil
      #  # Nils are ignored; they default to nil in constructor if/when a value is missing
      #  yaml.scalar "nil"
      when Bool
        yaml.scalar value
        # This case wont match
      when Int
        yaml.scalar value
      when Range(Int32, Int32)
        # TODO seems there is no support for range with step?
        yaml.scalar value # .begin.to_s+ ".."+ (value.exclusive? ? value.end- 1 : value.end).to_s
      when Array(Int32)
        yaml.scalar value.join ","
      when Enumerable
        # The IF is here to workaround a bug in Crystal <= 0.23:
        # https://github.com/crystal-lang/crystal/issues/4684
        # if value.class == Range(Int32, Int32)
        #  value = value.unsafe_as Range(Int32, Int32)
        #  yaml.scalar value # .begin.to_s+ ".."+ (value.exclusive? ? value.end- 1 : value.end).to_s
        # else
        # Done in this way because in Crystal <= 0.23 there is
        # no way to detect a step once it's set:
        # https://github.com/crystal-lang/crystal/issues/4695
        yaml.scalar value.join ","
        # end
      else
        raise "Cannot convert #{value.class} to YAML"
      end
    end

    def self.from_yaml(value : String | IO) : VirtualTime::Virtual
      parse_from value
    end

    def self.from_yaml(value : YAML::ParseContext, node : YAML::Nodes::Node) : VirtualTime::Virtual
      unless node.is_a?(YAML::Nodes::Scalar)
        node.raise "Expected scalar, not #{node.class}"
      end
      parse_from node.value
    end

    def self.parse_from(value)
      case value
      when "nil"
        nil
      when /^\d+$/
        value.to_i
      when /^(\d+,?)+$/
        value.split(",").map &.to_i
      when /^(\d+)\.\.\.(\d+)(?:\/(\d+))$/
        ($1.to_i...$2.to_i).step($3.to_i)
      when /^(\d+)\.\.\.(\d+)$/
        $1.to_i...$2.to_i
      when /^(\d+)\.\.(\d+)(?:\/(\d+))$/
        ($1.to_i..$2.to_i).step($3.to_i)
      when /^(\d+)\.\.(\d+)$/
        $1.to_i..$2.to_i
      when "true"
        true
      when "false"
        false
      when /^->/
        # XXX This one is here just to satisfy return type. It doesn't really work.
        ->(_v : Int32) { true }
      else
        raise ArgumentError.new "Invalid YAML input (#{value})"
      end
    end
  end

  # A custom to/from YAML converter for Time::Location.
  class TimeLocationConverter
    def self.to_yaml(value : Time::Location, yaml : YAML::Nodes::Builder)
      case value
      when Time::Location
        yaml.scalar value.name
      end
    end

    def self.from_yaml(value : String | IO) : Time::Location
      Time::Location.load value
    end

    def self.from_yaml(value : YAML::ParseContext, node : YAML::Nodes::Node) : Time::Location
      unless node.is_a?(YAML::Nodes::Scalar)
        node.raise "Expected scalar, not #{node.class}"
      end
      Time::Location.load node.value
    end
  end
end
