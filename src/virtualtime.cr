require "yaml"

class Steppable::StepIterator(T, L, B)
  getter current, limit, step, exclusive
end

class VirtualTime
  VERSION_MAJOR    = 1
  VERSION_MINOR    = 5
  VERSION_REVISION = 0
  VERSION          = [VERSION_MAJOR, VERSION_MINOR, VERSION_REVISION].join '.'

  include Comparable(Time)
  include YAML::Serializable

  alias Virtual = Nil | Bool | Int32 | Array(Int32) | Set(Int32) | Range(Int32, Int32) | Steppable::StepIterator(Int32, Int32, Int32) | VirtualProc
  alias VirtualProc = Proc(Int32, Bool)
  alias VTTuple = Tuple(Virtual, Virtual, Virtual, Virtual, Virtual, Virtual, Virtual, Virtual, Virtual, Virtual, Virtual, Time::Location?)
  alias TimeOrVirtualTime = Time | self

  # Macro to define properties with a common YAML converter
  macro virtual_time_property(*properties)
    {% for property in properties %}
      @[YAML::Field(converter: VirtualTime::VirtualConverter)]
      property {{ property.id }} : Virtual
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

  def initialize(*, @year, @week, @day_of_week = nil, @hour = nil, @minute = nil, @second = nil, @millisecond = nil, @nanosecond = nil, @location = nil, @default_match = true)
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
        # Ranges support O(1) membership tests; iterating them with `any?`
        # would be O(n) and is catastrophic for large ranges (e.g. nanoseconds).
        if a.is_a? Range(Int32, Int32)
          a.includes? b
        else
          a.any? { |e| e == b }
        end
      in Array(Int32), Set(Int32), Range(Int32, Int32), Steppable::StepIterator(Int32, Int32, Int32)
        # As above, never iterate a `Range`: test the other side's members
        # against it, or intersect two ranges arithmetically.
        if a.is_a? Range(Int32, Int32)
          if b.is_a? Range(Int32, Int32)
            RangeHelper.intersect? a, b
          else
            RangeHelper.restart(b).any? { |v| a.includes? v }
          end
        elsif b.is_a? Range(Int32, Int32)
          a.any? { |e| b.includes? e }
        else
          # `b` is re-created per element of `a` because a StepIterator is
          # consumed by iterating it.
          a.any? { |e| RangeHelper.restart(b).any? { |v| e == v } }
        end
      in VirtualProc
        a.any? { |e| b.call(e) }
      end
    in VirtualProc
      case b
      in Nil, Bool, Array(Int32), Set(Int32), Range(Int32, Int32), Steppable::StepIterator(Int32, Int32, Int32)
        matches? b, a, max
      in Int
        a.call b
      in VirtualProc
        raise ArgumentError.new "Proc to Proc comparison not supported (yet?)"
      end
    end
  end

  # Helpers:

  # Adjusts values to be suitable for use in comparisons.
  # At the moment, that includes converting negative values to offsets from end of range, reorganizing ranges so that begin <= end, and sorting Arrays and Sets.
  # If calling this function yourself, provide `max` whenever possible.
  @[AlwaysInline]
  def adjust_value(a : Virtual, max) # ameba:disable Metrics/CyclomaticComplexity
    case a
    in Nil, Bool, VirtualProc
      a
    in Int
      if max
        a < 0 ? max + a : a
      else
        a
      end
    in Array(Int32)
      if max && a.any?(&.<(0))
        a.map { |e| e < 0 ? max + e : e }.sort!
      else
        # Nothing to adjust; return the list itself rather than allocating a
        # sorted copy on every match.
        ArrayHelper.sorted?(a) ? a : a.sort
      end
    in Set(Int32)
      if max && a.any?(&.<(0))
        a.map { |e| e < 0 ? max + e : e }.sort!
      else
        a.to_a.sort!
      end
    in Range(Int32, Int32)
      if max && (a.begin < 0 || a.end < 0)
        ab = a.begin < 0 ? max + a.begin : a.begin
        ae = a.end < 0 ? max + a.end : a.end
        Range.new ab, ae, a.exclusive?
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
      # Unspecific Enumerable(Int32) is not part of `alias Virtual` and other,
      # more specific types are already listed with their own rules. Enable only
      # if some future need arises.
      # in Enumerable(Int32)
      #  if max
      #    a.map { |aa| aa < 0 ? max + aa : aa }
      #  else
      #    a
      #  end.sort
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

  # Materializing (returning new VTs with all fields materialized to specific, `Time`-compatible values)
  # Time: year, month, day, calendar_week, day_of_week, day_of_year, hour, minute, second, millisecond, nanosecond, location

  # Returns a new, "materialized" VirtualTime, i.e. an object where all fields have "materialized"/specific values
  #
  # `#location` and `#default_match?` are carried over to the new object; the
  # week number, day of week, and day of year are left unset, since they are
  # implied by the materialized date.
  def materialize(hint = Time.local.at_beginning_of_minute, strict = true)
    self.class.new **materialize_with_hint(hint, strict: strict), location: location, default_match: default_match?
  end

  # Materializes VT and returns fields needed to create a `Time` object.
  # This function does not check that the materialized values match the week number, day of week, and day of year constraints.
  # If you need those values checked, use `#to_time`.
  def materialize_with_hint(time : Time = Time.local.at_beginning_of_minute, carry = 0, strict = true)
    _nanosecond, _second, _minute, _hour, carry = materialize_time_with_hint time, carry, strict
    _day, _month, _year, carry = materialize_date_with_hint time, carry, strict

    # if carry > 0
    #  raise ArgumentError.new "Cannot find compliant materialized time"
    # end

    {year: _year, month: _month, day: _day, hour: _hour, minute: _minute, second: _second, nanosecond: _nanosecond}
  end

  # Materializes date part of current VT
  def materialize_date_with_hint(time : Time = Time.local.at_beginning_of_minute, carry = 0, strict = true)
    _day, carry = materialize(day, time.day + carry, 1, TimeHelper.days_in_month(time) + 1, strict)
    _month, carry = materialize(month, time.month + carry, 1, 13, strict)
    _year, carry = materialize(year, time.year + carry, 1, 10_000, strict)
    {_day, _month, _year, carry}
  end

  # Materializes time part of current VT
  def materialize_time_with_hint(time : Time = Time.local.at_beginning_of_minute, carry = 0, strict = true)
    _nanosecond, carry = materialize(nanosecond, time.nanosecond + carry, 0, 1_000_000_000, strict)
    _second, carry = materialize(second, time.second + carry, 0, 60, strict)
    _minute, carry = materialize(minute, time.minute + carry, 0, 60, strict)
    _hour, carry = materialize(hour, time.hour + carry, 0, 24, strict)
    {_nanosecond, _second, _minute, _hour, carry}
  end

  # Materializes a particular value with the help of a wanted/hint value.
  # If 'strict' is true and some of the `wanted` fields would not `match?` VT's requirements,
  # they are replaced/overriden with the first/earliest value from the allowed range.
  def materialize(allowed, wanted : Int, min, max = nil, strict = true) # ameba:disable Metrics/CyclomaticComplexity
    allowed = adjust_value allowed, max
    wanted = adjust_value wanted, max
    carry = 0

    case allowed
    in Nil
      unless default_match?
        raise ArgumentError.new "A VirtualTime with value `false` isn't materializable."
      end
      adjust_wanted_re_max
    in Bool
      unless allowed
        raise ArgumentError.new "A VirtualTime with value `false` isn't materializable."
      end
      adjust_wanted_re_max
    in Int
      adjust_wanted_re_max
      if !strict
        # wanted is OK
      else
        if max
          carry += 1 if wanted > allowed
          wanted = allowed
        end
      end
    in Range(Int32, Int32)
      adjust_wanted_re_max
      if max && (allowed.begin < 0 || allowed.end < 0)
        ab = allowed.begin < 0 ? max + allowed.begin : allowed.begin
        ae = allowed.end < 0 ? max + allowed.end : allowed.end
        allowed = Range.new ab, ae, allowed.exclusive?
      end
      if !strict || allowed.includes? wanted
      else
        carry += max && (wanted > allowed.begin) ? 1 : 0
        wanted = allowed.begin
      end
      # This covers Array(Int32) and Steppable::StepIterator(Int32,Int32,Int32)
    in Enumerable(Int32)
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
    in VirtualProc
      adjust_wanted_re_max
    end

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
  def ==(other : TimeOrVirtualTime)
    matches? other
  end

  # Compares `VirtualTime` to `Time` instance.
  #
  # Returns `0` if the time matches the `VirtualTime`, and `nil` otherwise.
  # A `VirtualTime` is a pattern without a meaningful position relative to a
  # specific point in time, so ordering operators (`<`, `>`, `<=`, `>=`)
  # always return `false` (`Comparable` semantics for an undefined ordering).
  def <=>(other : Time)
    matches?(other) ? 0 : nil
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

  # Converts a VirtualTime to a specific Time object that matches the VirtualTime.
  #
  # Value is converted using a time hint, which defaults to the current time.
  # Lists and ranges of values materialize to their min / begin value.
  #
  # Additionally, any requirements for week number, day of week, and day of year are also met,
  # possibly by doing multiple iterations to find a suitable date. The process is limited to
  # some max attempts of trying to find a value that simultaneously satisfies all constraints.
  def to_time(hint = Time.local.at_beginning_of_minute, strict = true)
    time = materialize_to_time hint, strict
    max_tries = 100
    tries = 0

    loop do
      tries += 1

      if week && day_of_week # Anchor deterministically using ISO week rules
        # ISO week 1 is the week containing Jan 4
        jan4 = Time.local(time.year, 1, 4, location: time.location)
        week1_monday = jan4.shift days: -(jan4.day_of_week.to_i - 1)
        target_week, _ = materialize week, time.calendar_week[1], 0, TimeHelper.weeks_in_year(time) + 1, strict
        target_dow, _ = materialize day_of_week, time.day_of_week.to_i, 1, 8, strict
        # Walk days with calendar arithmetic and rebuild the value with the
        # already-materialized time-of-day, so that neither the walk itself
        # nor DST transitions disturb the time part.
        date = week1_monday.shift days: (target_week - 1) * 7 + (target_dow - 1)
        time = Time.local(date.year, date.month, date.day, time.hour, time.minute, time.second, nanosecond: time.nanosecond, location: time.location)
      else # Apply incremental logic for partial constraints
        if week
          week_nr = time.calendar_week[1]
          value, _ = materialize(week, week_nr, 0, TimeHelper.weeks_in_year(time) + 1, strict)
          time += adjust_day(week_nr, value, TimeHelper.weeks_in_year(time)) * 7
        end
        if day_of_week
          current_dow = time.day_of_week.to_i
          value, _ = materialize(day_of_week, current_dow, 1, 8, strict)
          time += adjust_day(current_dow, value, 7)
        end
      end

      current_doy = time.day_of_year
      value, _ = materialize(day_of_year, current_doy, 1, TimeHelper.days_in_year(time) + 1, strict)
      time += adjust_day(current_doy, value, TimeHelper.days_in_year(time))

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

  # Materializes `self` into a `Time`, ignoring the week number, day of week,
  # and day of year constraints (which `#to_time` goes on to satisfy).
  private def materialize_to_time(hint : Time, strict : Bool) : Time
    timespec = materialize_with_hint hint, strict: strict
    Time.local **timespec, location: hint.location
  rescue e : ArgumentError
    raise ArgumentError.new "#{inspect} with hint #{hint} could not be materialized into a Time (#{e.message})"
  end

  # Creates `VirtualTime` from `Time`.
  # This can be useful to produce a VT with values filled in quickly, and then set some fields to more interesting values rather than fixed integers.
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

  # Sets all VT fields to nil
  def clear!
    clear_date!
    clear_time!
  end

  # Sets date-related VT fields to nil
  def clear_date!
    self.year = nil
    self.month = nil
    self.day = nil
    self.week = nil
    self.day_of_week = nil
    self.day_of_year = nil
    self
  end

  # Sets time-related VT fields to nil
  def clear_time!
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
  # This function is used only in tests so far.
  def expand
    ArrayHelper.expand(VTTuple.new year, month, day, week, day_of_week, day_of_year, hour, minute, second, millisecond, nanosecond, location).map { |v| self.class.new *(VTTuple.from v) }
  end

  # Iterator-related stuff

  # Produces closest-next `Time` that matches the current VT, starting with `from` + 1 nanosecond onwards.
  # (Because it always finds the "next" time, the default value is `at_end_of_minute` (:99).)
  def succ(from : Time = Time.local.at_end_of_minute)
    to_time from + 1.nanosecond
  end

  # Returns Iterator
  def step(interval = 1.minute, by = 1, from = Time.local.at_end_of_minute) : Iterator
    from = succ from
    StepIterator(self, Time::Span, Int32, Time).new(self, interval, by, from)
  end

  # END OF CLASS CODE

  # Iterator for generating successive `Time`s that match the VT constraints
  private class StepIterator(R, D, N, B)
    include Iterator(B)

    @virtualtime : R
    @interval : D
    @step : N
    @current : B
    @reached_end : Bool
    @at_start = true

    def initialize(@virtualtime, @interval = 1.minute, @step = 1, @current = virtualtime.succ, @reached_end = false)
    end

    def next
      return stop if @reached_end

      # The initial value is produced by `#initialize` (via `VirtualTime#succ`),
      # so the first call yields it rather than advancing.
      if @at_start
        @at_start = false
        return @current
      end

      @step.times do
        break if @reached_end
        # Or: - (@current.to_unix_ns % @interval.total_nanoseconds.to_i64 + 1).nanoseconds
        @current = @virtualtime.succ @current + @interval - 1.nanosecond
      rescue ArgumentError
        # No further Time satisfies the VT's constraints
        @reached_end = true
      end

      @reached_end ? stop : @current
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
      0
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

    # Returns number of days in current year. For a VT this is always `0` since value is not determinable
    def self.days_in_year(time : VirtualTime)
      0
    end
  end

  module RangeHelper
    # Returns the last value included in `range`, or `nil` if it contains no values.
    def self.last(range : Range(Int32, Int32)) : Int32?
      last = range.exclusive? ? range.end - 1 : range.end
      last < range.begin ? nil : last
    end

    # Returns whether the two ranges have at least one value in common.
    #
    # This is the O(1) counterpart of intersecting them by iteration, which
    # matters because VirtualTime ranges can be enormous (e.g. nanoseconds).
    def self.intersect?(a : Range(Int32, Int32), b : Range(Int32, Int32)) : Bool
      a_last, b_last = last(a), last(b)
      return false unless a_last && b_last
      (a.begin <= b_last) && (b.begin <= a_last)
    end

    # Returns `value` ready to be iterated from its first element.
    #
    # `Steppable::StepIterator`s are stateful and are consumed by iteration,
    # so they must be copied before every traversal; everything else is
    # returned as-is.
    def self.restart(value : Steppable::StepIterator(Int32, Int32, Int32))
      value.dup
    end

    # :ditto:
    def self.restart(value)
      value
    end
  end

  module ArrayHelper
    # Returns whether `list` is in ascending order.
    #
    # Used to skip allocating a sorted copy of a list that is already sorted,
    # which is the common case for hand-written rules like `day: [1, 15]`.
    def self.sorted?(list : Array(Int32)) : Bool
      list.each_cons_pair { |x, y| return false if x > y }
      true
    end

    # Expands ranges and other expandable types into a long list of all possible options.
    # E.g. [1, 2..3, 4..5] gets expanded into [[1, 2, 4], [1,2, 5], [1,3,4], [1,3,5]].
    # Used only for convenience in tests.
    def self.expand(list)
      options = list.map do |e|
        case e
        when Array
          e
        when Enumerable
          e.dup.to_a
        else
          [e]
        end
      end

      Indexable.cartesian_product options
    end
  end

  # A custom to/from YAML converter for VirtualTime.
  class VirtualConverter
    def self.to_yaml(value : VirtualTime::Virtual, yaml : YAML::Nodes::Builder)
      case value
      # Nils are ignored; they default to nil in the constructor if/when a value is missing
      when Bool
        yaml.scalar value
      when Int
        yaml.scalar value
      when Range(Int32, Int32)
        # `Range#to_s` already renders both `..` and `...` correctly
        yaml.scalar value
      when Steppable::StepIterator(Int32, Int32, Int32)
        # Emitted in the `begin..end/step` form that `.parse_from` accepts, so
        # that the step survives the round-trip. Listing the individual values
        # instead would both lose the step and, for a wide range, produce an
        # enormous document. Note that the iterator must not be traversed here:
        # it is stateful, and doing so would consume the value being saved.
        yaml.scalar "#{value.current}#{value.exclusive ? "..." : ".."}#{value.limit}/#{value.step}"
      when Array(Int32), Set(Int32)
        yaml.scalar value.join ","
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

    def self.parse_from(raw)
      value = raw.to_s.strip

      case value
      when "nil"
        nil
      when "true"
        true
      when "false"
        false
      when /^-?\d+$/
        value.to_i
      when /^-?\d+(?:\s*,\s*-?\d+)*$/
        value.split(/\s*,\s*/).map(&.to_i)
      when /^(-?\d+)\.\.\.(-?\d+)(?:\/(\d+))$/
        ($1.to_i...$2.to_i).step($3.to_i)
      when /^(-?\d+)\.\.\.(-?\d+)$/
        $1.to_i...$2.to_i
      when /^(-?\d+)\.\.(-?\d+)(?:\/(\d+))$/
        ($1.to_i..$2.to_i).step($3.to_i)
      when /^(-?\d+)\.\.(-?\d+)$/
        $1.to_i..$2.to_i
      when /^->/
        # Deserializing a Proc would silently produce a wrong (match-everything)
        # rule, so it is explicitly not supported.
        raise ArgumentError.new("Procs cannot be deserialized from YAML; set Proc-based values in code after loading")
      else
        raise ArgumentError.new("Invalid YAML input (#{value})")
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

  # Search provides monotonic, DST-safe, policy-free temporal traversal suitable for scheduling.
  # Stateless. Not related to other methods above. Advances by at least 1 step before evaluation.
  module Search
    # Moves forward from `base` by repeated application of `step`
    # (successor behavior: first candidate is base + step).
    #
    # Returns:
    # - `Result::Found` holding the Time::Span delta to the first unblocked candidate
    # - `Result::OutOfBounds` / `Result::Blocked` if the respective bound is exceeded
    # - `Result::InvalidStep` if `step` is zero
    #
    # Notes:
    # - step must be non-zero
    # - max_shift bounds the returned delta (inclusive)
    # - max_shifts bounds the number of step applications (inclusive)
    # - stepping is done on Time values (DST-safe)
    # - the search is only as bounded as its arguments: if `domain`, `max_shift`,
    #   and `max_shifts` are all nil and every candidate is blocked, it never
    #   returns. Supply at least one bound unless the block is certain to
    #   eventually accept a candidate.
    def self.shift_from_base(base : Time, step : Time::Span, *, domain : Domain? = nil, max_shift : Time::Span? = nil, max_shifts : Int32? = nil, &blocked : Time -> Bool) : Result::Result
      return Result::InvalidStep.new if step == 0.seconds
      return Result::OutOfBounds.new if max_shifts && max_shifts <= 0

      current = base
      delta = Time::Span.zero
      shifts = 0

      loop do
        # successor step
        current = current + step
        delta += step
        shifts += 1

        return Result::Blocked.new if max_shifts && shifts > max_shifts
        return Result::OutOfBounds.new if max_shift && delta.abs > max_shift

        if domain && !domain.contains?(current)
          return Result::OutOfBounds.new
        end

        unless blocked.call(current)
          raise "BUG: shift_from_base produced zero delta" if delta == 0.seconds
          return Result::Found.new(delta)
        end
      end
    end

    # Inverse reachability check: determine backwards whether `target` can be obtained as `base + delta`,
    # stepping by `step`. Returns bool value.
    #
    # Notes:
    # - successor-based: first base is `target - step`
    # - max_shift bounds the produced delta (inclusive)
    # - max_shifts bounds number of step applications (inclusive)
    # - stepping is done on Time values (DST-safe)
    def self.shifted_from_base?(target : Time, step : Time::Span, *, max_shift : Time::Span? = nil, max_shifts : Int32, &producer : Time -> Time::Span?) : Bool
      return false if step == 0.seconds
      return false if max_shifts <= 0

      # If caller does not supply a max_shift, the max delta is still bounded by
      # the maximum number of step applications.
      effective_max_shift = max_shift || (step.abs * max_shifts)

      current = target
      shifts = 0

      loop do
        # successor behavior is in inverse direction: first base is target - step
        current = current - step
        shifts += 1

        return false if shifts > max_shifts

        if produced = producer.call(current)
          # produced must itself be a valid delta and must reach the target
          if produced.abs <= effective_max_shift && current + produced == target
            return true
          end
        end

        # Optional: also ensure we don't walk bases so far away that even a maximal
        # produced delta couldn't reach the target.
        # Distance from current base to target is exactly shifts * step (in span form):
        distance = target - current
        return false if distance.abs > effective_max_shift
      end
    end

    # :ditto:
    @[Deprecated("Use `.shifted_from_base?` instead")]
    def self.is_shifted_from_base?(target : Time, step : Time::Span, *, max_shift : Time::Span? = nil, max_shifts : Int32, &producer : Time -> Time::Span?) : Bool # ameba:disable Naming/PredicateName
      shifted_from_base?(target, step, max_shift: max_shift, max_shifts: max_shifts, &producer)
    end
  end

  module Result
    # Result types for Search operations. Intentionally orthogonal to VirtualDate's policies.
    abstract struct Result
    end

    struct Found < Result
      getter delta : Time::Span

      def initialize(@delta : Time::Span)
      end
    end

    struct OutOfBounds < Result
    end

    struct Blocked < Result
    end

    # NOTE: Result-returning APIs return `InvalidStep`, but bool ones return `false`.
    struct InvalidStep < Result
    end
  end

  # Extension point for bounding `Search` traversal to a set of acceptable
  # `Time`s. Subclass and override `#contains?` to restrict the search; passing
  # `domain: nil` (the default) disables the check entirely.
  abstract struct Domain
    abstract def contains?(time : Time) : Bool
  end
end
