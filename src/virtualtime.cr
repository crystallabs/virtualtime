require "yaml"

class Steppable::StepIterator(T, L, B)
  getter current, limit, step, exclusive
end

class VirtualTime
  VERSION_MAJOR    = 1
  VERSION_MINOR    = 2
  VERSION_REVISION = 0
  VERSION          = [VERSION_MAJOR, VERSION_MINOR, VERSION_REVISION].join '.'

  include Comparable(Time)
  include YAML::Serializable

  # XXX Use Int instead of Int32 when it becomes possible in unions in Crystal
  # XXX Possibly add Enumerable(Int32) and remove more specific types after https://github.com/crystal-lang/crystal/issues/14047

  alias Virtual = Nil | Bool | Int32 | Array(Int32) | Set(Int32) | Range(Int32, Int32) | Steppable::StepIterator(Int32, Int32, Int32) | VirtualProc
  alias VirtualProc = Proc(Int32, Bool)
  alias VTTuple = Tuple(Virtual, Virtual, Virtual, Virtual, Virtual, Virtual, Virtual, Virtual, Virtual, Virtual, Virtual, Time::Location?)
  alias TimeOrVirtualTime = Time | self

  # Macro to define properties with a common YAML converter
  macro virtual_time_property(*properties)
    {% for property in properties %}
      @[YAML::Field(converter: VirtualTime::VirtualConverter)]
      property {{property.id}} : Virtual # default comment or value
    {% end %}
  end

  virtual_time_property year, month, day, week, day_of_week, day_of_year, hour, minute, second, millisecond, nanosecond

  # Location/timezone in which to perform matching, if any
  @[YAML::Field(converter: VirtualTime::TimeLocationConverter)]
  property location : Time::Location?

  # Instance-default match result if one of field values matched is `nil`
  property? default_match : Bool = true

  def initialize(@year = nil, @month = nil, @day = nil, @hour = nil, @minute = nil, @second = nil, *, @millisecond = nil, @nanosecond = nil, @day_of_week = nil, @day_of_year = nil, @week = nil, @location = nil, @default_match = true)
  end

  def initialize(*, @year, @week, @day_of_week = nil, @hour = nil, @minute = nil, @second = nil, @millisecond = nil, @nanosecond = nil, @location = ni, @default_match = true)
  end

  def initialize(@year, @month, @day, @week, @day_of_week, @day_of_year, @hour, @minute, @second, @millisecond, @nanosecond, @location, @default_match = true)
  end

  # Matching

  # Returns whether `VirtualTime` matches the specified time
  def matches?(time : TimeOrVirtualTime = Time.local)
    time = adjust_location time
    matches_date?(time) && matches_time?(time)
  end

  # Returns whether `VirtualTime` matches the date part of specified time
  def matches_date?(time : TimeOrVirtualTime = Time.local)
    time = adjust_location time
    matches?(year, time.year, 10_000) &&
      matches?(month, time.month, 13) &&
      matches?(day, time.day, TimeHelper.days_in_month(time) + 1) &&
      matches?(week, TimeHelper.week(time), TimeHelper.weeks_in_year(time) + 1) &&
      matches?(day_of_week, TimeHelper.day_of_week(time), 8) &&
      matches?(day_of_year, TimeHelper.day_of_year(time), TimeHelper.days_in_year(time) + 1)
  end

  # Returns whether `VirtualTime` matches the time part of specified time
  def matches_time?(time : TimeOrVirtualTime = Time.local)
    time = adjust_location time
    matches?(hour, time.hour, 24) &&
      matches?(minute, time.minute, 60) &&
      matches?(second, time.second, 60) &&
      matches?(millisecond, time.millisecond, 1_000) &&
      matches?(nanosecond, time.nanosecond, 1_000_000_000)
  end

  # Performs matching between VirtualTime and other supported types
  def matches?(a, b, max = nil) : Bool
    a = adjust_value a, max
    b = adjust_value b, max

    case a
    in Nil
      b == false ? false : default_match?
    in Bool
      b == false ? false : a
    in Int
      case b
      in Nil, Bool, Array(Int32), Set(Int32), Range(Int32, Int32), Steppable::StepIterator(Int32, Int32, Int32)
        matches? b, a, max
      in Int
        a == b
      in VirtualProc
        b.call a
      end
    in Array(Int32), Set(Int32), Range(Int32, Int32), Steppable::StepIterator(Int32, Int32, Int32)
      a = a.dup if a.is_a? Steppable::StepIterator(Int32, Int32, Int32)
      case b
      in Nil, Bool
        matches? b, a, max
      in Int
        a.each do |aa|
          return true if aa == b
        end
        false
      in Array(Int32), Set(Int32), Range(Int32, Int32), Steppable::StepIterator(Int32, Int32, Int32)
        a.each do |aa|
          bb = b.is_a?(Steppable::StepIterator(Int32, Int32, Int32)) ? b.dup : b
          bb.each do |bbb|
            return true if aa == bbb
          end
        end
        false
      in VirtualProc
        a.each do |aa|
          return true if b.call aa
        end
        false
      end
    in VirtualProc
      case b
      in Nil, Bool, Array(Int32), Set(Int32), Range(Int32, Int32), Steppable::StepIterator(Int32, Int32, Int32)
        matches? b, a, max
      in Int32
        a.call b
      in VirtualProc
        raise ArgumentError.new "Proc to Proc comparison not supported (yet?)"
      end
    end
  end

  # Helpers:

  # Adjusts values to be suitable for use in comparisons.
  # At the moment, that includes converting negative values to offsets from end of range, reorganizing ranges so ttat begin <= end, and sorting Arrays and Sets,
  # If calling this function yourself, provide `max` whenever possible.
  @[AlwaysInline]
  def adjust_value(a, max)
    case a
    in Nil, Bool
      a
    in Int
      if max
        a < 0 ? max + a : a
      else
        a
      end
    in Array(Int32), Set(Int32)
      if max
        a.map { |aa| aa < 0 ? max + aa : aa }
      else
        a.to_a
      end.sort
    in Range(Int32, Int32)
      if max && (a.begin < 0 || a.end < 0)
        ab = a.begin < 0 ? max + a.begin : a.begin
        ae = a.end < 0 ? max + a.end : a.end
        ab..ae
      else
        a
      end
    in Steppable::StepIterator(Int32, Int32, Int32)
      if max && (a.current < 0 || a.limit < 0)
        ab = a.current < 0 ? max + a.current : a.current
        ae = a.limit < 0 ? max + a.limit : a.limit
        Steppable::StepIterator(Int32, Int32, Int32).new ab, ae, a.step, a.exclusive
      else
        a
      end
    in Enumerable(Int32)
      if max
        a.map { |aa| aa < 0 ? max + aa : aa }
      else
        a
      end.sort
    in VirtualProc, Proc(Bool)
      a
    end
  end

  # Ensures that `Time`'s timezone is equal to VT's timezone.
  # Raises ArgumentError if comparing two VTs with different timezones.
  @[AlwaysInline]
  def adjust_location(time)
    if time.is_a? Time
      if (l = location) && (time.location != l)
        time = time.in l
      end
    else
      if location != time.location
        raise ArgumentError.new "Comparing VirtualTimes with different locations/timezones not supported (yet?)"
      end
    end
    time
  end

  # If `max` is specified, adjusts `hint` in respect to `max`.
  #
  # Specifically, if `hint` is equal or greater than `max`, it wraps it around
  # by increasing `carry` by 1 and reducing `hint` by `max`.
  #
  # The current implementation does not support wrapping more than once, e.g.
  # a wanted of `120` with a max of `60` would produce an error.
  # That is because some of `VirtualTime`s fields (like e.g. `day`) do not have
  # a fixed max value (it can be 28, 29, 30, or 31, depending on month).
  @[AlwaysInline]
  macro adjust_wanted_re_max
    if max
      limit = (2*max-2*min).abs
      if wanted.abs >= limit
        raise ArgumentError.new "A `wanted.abs` value #{wanted.abs} must not be be >= #{limit} (>= (2*max-2*min).abs)."
      end
      if wanted >= max
        wanted -= max - min
        carry += 1
      end
    end
  end

  # Materializing
  # Time: year, month, day, calendar_week, day_of_week, day_of_year, hour, minute, second, millisecond, nanosecond, location

  # Returns a new, "materialized" VirtualTime, i.e. an object where all fields have "materialized"/specific values
  def materialize(hint = Time.local, strict = true)
    self.class.new **materialize_with_hint(hint)
  end

  # Materializes VT and returns fields needed to create a `Time` object.
  # This function does not check that the materialized values match the week number, day of week, and day of year constraints.
  # If you need those values checked, use `#to_time`.
  def materialize_with_hint(time : Time, carry = 0)
    _nanosecond, _second, _minute, _hour, carry = materialize_time_with_hint time, carry
    _day, _month, _year, carry = materialize_date_with_hint time, carry

    if carry > 0
      raise ArgumentError.new "Cannot find compliant materialized time"
    end

    {year: _year, month: _month, day: _day, hour: _hour, minute: _minute, second: _second, nanosecond: _nanosecond}
  end

  # Materialize date part of current VT
  def materialize_date_with_hint(time : Time, carry = 0)
    _day, carry = materialize(day, time.day + carry, 1, TimeHelper.days_in_month(time) + 1)
    _month, carry = materialize(month, time.month + carry, 1, 13)
    _year, carry = materialize(year, time.year + carry, 1, 10_000)
    {_day, _month, _year, carry}
  end

  # Materialize time part of current VT
  def materialize_time_with_hint(time : Time, carry = 0)
    _nanosecond, carry = materialize(nanosecond, time.nanosecond + carry, 0, 1_000_000_000)
    _second, carry = materialize(second, time.second + carry, 0, 60)
    _minute, carry = materialize(minute, time.minute + carry, 0, 60)
    _hour, carry = materialize(hour, time.hour + carry, 0, 24)
    {_nanosecond, _second, _minute, _hour, carry}
  end

  # Materialize a particular value with the help of a wanted/wanted value.
  # If 'strict' is true and wanted value does not satisfy predefined range or requirements, it is replaced with the first/earliest value from allowed range.
  def materialize(allowed : Nil, wanted : Int32, min, max = nil, strict = true)
    allowed = adjust_value allowed, max
    wanted = adjust_value wanted, max

    unless default_match?
      raise ArgumentError.new "A VirtualTime with value `false` isn't materializable."
    end
    carry = 0
    adjust_wanted_re_max
    {wanted, carry}
  end

  # :ditto:
  def materialize(allowed : Bool, wanted : Int32, min, max = nil, strict = true)
    allowed = adjust_value allowed, max
    wanted = adjust_value wanted, max

    unless allowed
      raise ArgumentError.new "A VirtualTime with value `false` isn't materializable."
    end
    carry = 0
    adjust_wanted_re_max
    {wanted, carry}
  end

  # :ditto:
  def materialize(allowed : Int, wanted : Int32, min, max = nil, strict = true)
    allowed = adjust_value allowed, max
    wanted = adjust_value wanted, max

    carry = 0
    adjust_wanted_re_max
    if !strict
      # wanted is OK
    else
      if max
        carry += 1 if wanted > allowed
        wanted = allowed
      end
    end
    {wanted, carry}
  end

  # :ditto:
  def materialize(allowed : Range(Int, Int), wanted : Int32, min, max = nil, strict = true)
    allowed = adjust_value allowed, max
    wanted = adjust_value wanted, max

    carry = 0
    adjust_wanted_re_max
    # XXX adjust_range...
    if max && (allowed.begin < 0 || allowed.end < 0)
      ab = allowed.begin < 0 ? max + allowed.begin : allowed.begin
      ae = allowed.end < 0 ? max + allowed.end : allowed.end
      allowed = ab..ae
    end
    if !strict || allowed.includes? wanted
    else
      carry += max && (wanted > allowed.begin) ? 1 : 0
      wanted = allowed.begin
    end
    {wanted, carry}
  end

  # :ditto:
  def materialize(allowed : Enumerable(Int), wanted : Int32, min, max = nil, strict = true)
    allowed = adjust_value allowed, max
    wanted = adjust_value wanted, max

    carry = 0
    adjust_wanted_re_max
    allowed = allowed.dup.to_a
    if max && allowed.any?(&.<(0))
      allowed = allowed.map { |e| e < 0 ? max + e : e }
    end
    if !strict || allowed.includes? wanted
    else
      if candidate = allowed.dup.find &.>=(wanted)
        wanted = candidate
      else
        carry += max && (wanted > allowed.min) ? 1 : 0
        wanted = allowed.min
      end
    end
    {wanted, carry}
  end

  # :ditto:
  def materialize(allowed : Proc(Virtual, Bool), wanted : Int32, min, max = nil, strict = true)
    allowed = adjust_value allowed, max
    wanted = adjust_value wanted, max

    carry = 0
    adjust_wanted_re_max
    {wanted, carry}
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
  #
  # Alias for `matches?`.
  @[AlwaysInline]
  def ==(time : TimeOrVirtualTime = Time.local)
    matches? time
  end

  # Compares `VirtualTime` to `Time` instance
  def <=>(other : Time)
    # This is one possible implementation:
    # to_time(other) <=> other
    # Another could be:
    matches?(other) ? 1 : -1
  end

  # "Rewinds" `day` forward enough to reach `acceptable_day`.
  #
  # It wraps around `wrap_day`, so e.g. `adjust_day(25, 5, 30)` returns `10.days`
  def adjust_day(day : Int, acceptable_day : Int, wrap_day : Int)
    amount = 0

    if acceptable_day > day
      amount = (acceptable_day - day)
    elsif acceptable_day < day
      amount = (wrap_day - day) + acceptable_day
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
  # some max attempts of trying to find a value that simultaneously satisfies all constraints.
  def to_time(hint = Time.local, strict = true)
    begin
      time = Time.local **materialize_with_hint(hint), location: hint.location
    rescue ArgumentError
      raise ArgumentError.new "#{inspect} with hint #{hint} produced an invalid Time"
    end
    max_tries = 100
    tries = 0

    loop do
      tries += 1

      week_nr = time.calendar_week[1]
      value, _ = materialize(week, week_nr, 0, TimeHelper.weeks_in_year(time) + 1, strict)
      time += adjust_day(week_nr, value, TimeHelper.weeks_in_year(time)) * 7

      day = time.day_of_week.to_i
      value, _ = materialize(day_of_week, day, 1, 8, strict)
      time += adjust_day(day, value, 7)

      day = time.day_of_year
      value, _ = materialize(day_of_year, day, 1, TimeHelper.days_in_year(time) + 1, strict)
      time += adjust_day(day, value, TimeHelper.days_in_year(time))

      break if matches_date?(time)

      if tries >= max_tries
        # TODO maybe some other error, not arg err
        raise ArgumentError.new "Could not find a date that satisfies week number, day of week, and day of year after #{max_tries} iterations (reached #{time})"
      end

      # If it didn't match, then since we are only checking for days in this loop, advance by 1 day and retry.
      time += 1.day
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

  # Sets date-related fields to nil
  def nil_date!
    self.year = nil
    self.month = nil
    self.day = nil
    self.week = nil
    self.day_of_week = nil
    self.day_of_year = nil
    self
  end

  # Sets time-related fields to nil
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
  #
  # This function is used only in tests.
  def expand
    ArrayHelper.expand(VTTuple.new year, month, day, week, day_of_week, day_of_year, hour, minute, second, millisecond, nanosecond, location).map { |v| self.class.new *(VTTuple.from v) }
  end

  # Iterator-related stuff

  # Produces closest-next `Time` that matches the current VT, starting with `from` + 1 nanosecond onwards
  def succ(from : Time = Time.local)
    to_time from + 1.nanosecond
  end

  # Returns Iterator
  def step(interval = 1.nanosecond, by = 1, from = Time.local.at_end_of_second) : Iterator
    from = succ from
    StepIterator(self, Time::Span, Int32, Time).new(self, interval, by, from)
  end

  # Iterator for generating successive `Time`s that match the VT constraints
  private class StepIterator(R, D, N, B)
    include Iterator(B)

    @virtualtime : R
    @interval : D
    @step : N
    @current : B
    @reached_end : Bool
    @at_start = true

    def initialize(@virtualtime, @interval, @step, @current = virtualtime.succ, @reached_end = false)
    end

    def next
      return stop if @reached_end

      end_value = nil

      if @at_start
        @at_start = false

        if end_value
          if @current >= end_value
            @reached_end = true
            return stop
          end
        end

        return @current
      end

      if end_value.nil? || @current < end_value
        if end_value && (@current >= end_value)
          @reached_end = true
          return stop
        end

        @step.times do
          begin
            @current = @virtualtime.succ @current + @interval - 1.nanosecond # Or: - (@current.to_unix_ns % @interval.total_nanoseconds.to_i64 + 1).nanoseconds
          rescue ArgumentError
            end_value = @current
          end
        end

        if end_value && (@current >= end_value)
          @reached_end = true
          stop
        else
          @current
        end
      else
        @reached_end = true
        stop
      end
    end
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
    def self.weeks_in_year(time : Time)
      (time.at_end_of_year.day_of_year - time.day_of_week.to_i + 10) // 7
    end

    # :nodoc:
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

    # Returns number of days in month of specified `time`
    def self.days_in_month(time : Time)
      Time.days_in_month time.year, time.month
    end

    # :ditto:
    def self.days_in_month(time : VirtualTime)
      nil
    end

    # Returns week number (0..53) of specified `time`
    def self.week(time : Time)
      time.calendar_week[1].to_i
    end

    # :ditto:
    def self.week(time : VirtualTime)
      time.week
    end

    # Returns day of week of specified `time`
    def self.day_of_week(time : Time)
      time.day_of_week.to_i
    end

    # :ditto:
    def self.day_of_week(time : VirtualTime)
      time.day_of_week
    end

    # Returns day of year of specified `time`
    def self.day_of_year(time)
      time.day_of_year
    end

    # Returns number of days in current year
    def self.days_in_year(time : Time)
      Time.days_in_year time.year
    end

    # Returns number of days in current year. For a VT this is always `nil` since value is not determinable
    def self.days_in_year(time : VirtualTime)
      nil
    end
  end

  module ArrayHelper
    # Expands ranges and other expandable types into a long list of all possible options.
    # E.g. [1, 2..3, 4..5] gets expanded into [[1, 2, 4], [1,2, 5], [1,3,4], [1,3,5]].
    # Used only for convenience in tests.
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
      when Array(Int32), Set(Int32)
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
