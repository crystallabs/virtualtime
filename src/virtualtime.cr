require "yaml"

class Steppable::StepIterator(T, L, B)
  getter current, limit, step, exclusive
end

class VirtualTime
  VERSION_MAJOR    = 1
  VERSION_MINOR    = 8
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

  # Names of the value-carrying properties, in the order they are serialized
  FIELDS = %w[year month day week day_of_week day_of_year hour minute second millisecond nanosecond]

  virtual_time_property year, month, day, week, day_of_week, day_of_year, hour, minute, second, millisecond, nanosecond

  # Location/timezone in which to perform matching, if any
  @[YAML::Field(converter: VirtualTime::TimeLocationConverter)]
  property location : Time::Location?

  # Instance-default match result if one of field values matched is `nil`
  property? default_match : Bool = true

  # Writes `self` as a YAML mapping.
  #
  # The mapping is built here rather than generated because
  # `YAML::Serializable` tests a converter-backed property for truthiness
  # before handing it to the converter: a field set to `false` (never match)
  # would be written out as null and read back as `nil` (match anything),
  # inverting the rule. Reading still goes through `VirtualConverter`, which
  # the `@[YAML::Field]` annotations above take care of.
  def to_yaml(yaml : YAML::Nodes::Builder)
    yaml.mapping(reference: self) do
      {% for field in FIELDS %}
        value = @{{ field.id }}
        unless value.nil?
          yaml.scalar {{ field }}
          VirtualConverter.to_yaml value, yaml
        end
      {% end %}

      if loc = @location
        yaml.scalar "location"
        TimeLocationConverter.to_yaml loc, yaml
      end

      yaml.scalar "default_match"
      @default_match.to_yaml yaml
    end
  end

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
    # How many days a month or a year holds, and how many weeks a year has, is
    # only knowable for an actual `Time`. Against another `VirtualTime` those
    # maxima are dropped, so that a negative value stays negative and matches
    # the same negative on the other side rather than being rewritten -- with a
    # max of `0 + 1` a `day: -1` would become `0`, a value no date ever has.
    concrete = time.is_a? Time
    # An unconstrained field on the other side answers to that side's own
    # `#default_match?`, so that which of the two is asked does not matter.
    other = time.is_a?(Time) ? default_match? : time.default_match?

    matches?(year, time.year, 10_000, b_default: other) &&
      matches?(month, time.month, 13, b_default: other) &&
      matches?(day, time.day, concrete ? TimeHelper.days_in_month(time) + 1 : nil, b_default: other) &&
      matches?(week, TimeHelper.week(time), concrete ? TimeHelper.weeks_in_year(time) + 1 : nil, b_default: other) &&
      matches?(day_of_week, TimeHelper.day_of_week(time), 8, b_default: other) &&
      matches?(day_of_year, TimeHelper.day_of_year(time), concrete ? TimeHelper.days_in_year(time) + 1 : nil, b_default: other)
  end

  # Returns whether `VirtualTime` matches the time part of specified time
  def matches_time?(time : TimeOrVirtualTime = Time.local)
    time = adjust_location time
    other = time.is_a?(Time) ? default_match? : time.default_match?

    matches?(hour, time.hour, 24, b_default: other) &&
      matches?(minute, time.minute, 60, b_default: other) &&
      matches?(second, time.second, 60, b_default: other) &&
      matches?(millisecond, time.millisecond, 1_000, b_default: other) &&
      matches?(nanosecond, time.nanosecond, 1_000_000_000, b_default: other)
  end

  # Performs matching between VirtualTime and other supported types
  #
  # An unconstrained (nil) value is governed by the `#default_match?` of the
  # `VirtualTime` it belongs to. `a` is this one's own field, so `a_default`
  # defaults to this one's setting; `b_default` names the setting on the other
  # side, and only differs when matching against another `VirtualTime` that
  # was built with a different one.
  def matches?(a, b, max = nil, a_default : Bool = default_match?, b_default : Bool = default_match?) : Bool
    matches_adjusted? adjust_value(a, max), adjust_value(b, max), a_default, b_default
  end

  # Matching proper, on two values `#adjust_value` has already normalized.
  #
  # Swapping the sides happens here rather than by calling `#matches?` again,
  # because adjusting twice is not idempotent for a negative value beyond
  # `max`: with a `max` of 24 a `-30` becomes `-6` and then `18`, which would
  # then spuriously equal a literal 18. The two sides' `default_match?`
  # settings travel with them across the swap, so that which side is asked
  # makes no difference to the answer.
  private def matches_adjusted?(a, b, a_default : Bool, b_default : Bool) : Bool # ameba:disable Metrics/CyclomaticComplexity
    # A value that permits nothing matches nothing, whichever side it is on and
    # whatever it is held against: `false`, an empty list, and a range or
    # stepped range that yields no value all say the same thing.
    # That includes a range like `10..-7` met without a max (the VT-vs-VT
    # path): its raw form holds no values, and raw values are all that plane
    # compares -- exactly as the specs pin down.
    return false if permits_nothing?(a) || permits_nothing?(b)

    case a
    in Nil
      # Two unconstrained fields meet only if both sides let an unconstrained
      # one through; answering with one side's setting alone would make the
      # comparison depend on which of the two was asked.
      b.nil? ? (a_default && b_default) : a_default
    in Bool
      # A nil on the other side is the unconstrained case, and the
      # `#default_match?` of the side it came from governs that; deciding it
      # here would make matching asymmetric whenever the two disagree.
      b.nil? ? (b_default && a) : a
    in Int
      case b
      in Nil, Bool, Array(Int32), Set(Int32), Range(Int32, Int32), Steppable::StepIterator(Int32, Int32, Int32)
        matches_adjusted? b, a, b_default, a_default
      in Int
        a == b
      in VirtualProc
        b.call a
      end
    in Array(Int32), Set(Int32), Range(Int32, Int32), Steppable::StepIterator(Int32, Int32, Int32)
      case b
      in Nil, Bool
        matches_adjusted? b, a, b_default, a_default
      in Int
        # Ranges support O(1) membership tests; iterating them with `any?`
        # would be O(n) and is catastrophic for large ranges (e.g. nanoseconds).
        case a
        when Range(Int32, Int32)
          a.includes? b
        when Steppable::StepIterator(Int32, Int32, Int32)
          RangeHelper.includes? a, b
        else
          a.includes? b
        end
      in Array(Int32), Set(Int32), Range(Int32, Int32), Steppable::StepIterator(Int32, Int32, Int32)
        # As above, never iterate a `Range` or a wide stepped range: test the
        # other side's members against it, or intersect arithmetically.
        if a.is_a? Range(Int32, Int32)
          case b
          when Range(Int32, Int32)
            RangeHelper.intersect? a, b
          when Steppable::StepIterator(Int32, Int32, Int32)
            # First member of the progression at or past the range's begin
            candidate = RangeHelper.first_from b, a.begin
            a_last = RangeHelper.last a
            !candidate.nil? && !a_last.nil? && candidate <= a_last
          else
            b.any? { |e| a.includes? e }
          end
        elsif b.is_a? Range(Int32, Int32)
          a.any? { |e| b.includes? e }
        elsif b.is_a? Steppable::StepIterator(Int32, Int32, Int32)
          a.any? { |e| RangeHelper.includes? b, e }
        else
          a.any? { |e| b.includes? e }
        end
      in VirtualProc
        # A proc can only be asked value by value, and a range can span a
        # second's worth of nanoseconds. The scan is bounded by the same
        # constant `#materialize` uses for its own proc scans: a match inside
        # the bound still answers true, and past it the comparison is refused
        # rather than left to burn hundreds of millions of calls -- answering
        # `false` for values never asked about would be silently wrong.
        if (count = RangeHelper.count(a)) && count > MAX_PROC_SCAN
          scanned = 0
          a.each do |e|
            return true if b.call(e)
            scanned += 1
            break if scanned >= MAX_PROC_SCAN
          end

          raise ArgumentError.new "Comparing a Proc to a range of #{count} values is not supported (no match within the first #{MAX_PROC_SCAN})"
        end

        a.any? { |e| b.call(e) }
      end
    in VirtualProc
      case b
      in Nil, Bool, Array(Int32), Set(Int32), Range(Int32, Int32), Steppable::StepIterator(Int32, Int32, Int32)
        matches_adjusted? b, a, b_default, a_default
      in Int
        a.call b
      in VirtualProc
        raise ArgumentError.new "Proc to Proc comparison not supported (yet?)"
      end
    end
  end

  # Returns whether `value` allows nothing through: `false`, an empty list, or
  # a range or stepped range that yields no value.
  #
  # Every test is arithmetic rather than by iteration -- this sits on the hot
  # path of every comparison, and a range can span a whole second's worth of
  # nanoseconds.
  @[AlwaysInline]
  private def permits_nothing?(value) : Bool
    case value
    when false
      true
    when Range(Int32, Int32)
      RangeHelper.last(value).nil?
    when Array(Int32), Set(Int32)
      value.empty?
    when Steppable::StepIterator(Int32, Int32, Int32)
      RangeHelper.empty_step? value
    else
      false
    end
  end

  # Helpers:

  # Adjusts values to be suitable for use in comparisons.
  # At the moment, that includes converting negative values to offsets from end of range, and sorting Arrays and Sets.
  # If calling this function yourself, provide `max` whenever possible.
  #
  # A range whose begin exceeds its end is left as it is, and matches nothing:
  # wrapping ranges are not supported, so `hour: -1..1` is an empty rule rather
  # than "23:00 through 01:00". Write those as two rules, or as a list.
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
        RangeHelper.restart a
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
    # The new object carries this one's location, so the values filled in from
    # the hint have to be read in that same zone -- as `#to_time` does too.
    if (loc = location) && hint.location != loc
      hint = hint.in loc
    end

    self.class.new **materialize_with_hint(hint, strict: strict), location: location, default_match: default_match?
  end

  # Materializes VT and returns fields needed to create a `Time` object.
  # This function does not check that the materialized values match the week number, day of week, and day of year constraints.
  # If you need those values checked, use `#to_time`.
  def materialize_with_hint(time : Time = Time.local.at_beginning_of_minute, carry = 0, strict = true)
    spec = materialize_spec time, carry, strict

    # A day below the calendar's floor is the marker `#materialize` leaves
    # when the day rule allows nothing in the month it was sized by --
    # `day: -16..15` in a 31-day month. `#to_time` retries in other months;
    # this API answers for the hint it was given, and a spec that cannot
    # become a `Time` is no answer.
    if spec[:day] < 1
      raise ArgumentError.new "no allowed day exists in #{spec[:year]}-#{spec[:month]} for #{inspect} (hint #{time}); #to_time searches beyond the hint's month"
    end

    spec
  end

  # :ditto: but hands back the below-floor day sentinel instead of raising,
  # for the callers whose retry machinery moves the search to another month.
  private def materialize_spec(time : Time, carry = 0, strict = true) # ameba:disable Metrics/CyclomaticComplexity
    spec = materialize_fields time, carry, strict

    # A `#day` is sized by the month it lands in, and the first pass sized it
    # by the hint's own -- a different month whenever the date moved, in either
    # direction. The restart below only ever notices a move *forward*; a
    # `#year` naming a bygone year moves it back, where nothing has advanced
    # for the restart to see and the day would keep a size no month it reached
    # ever had.
    # The clock goes along only where the re-size stays in the month the hint
    # was about or reaches back before it. Carrying it into a *later* month
    # would floor every constrained time-of-day field at a clock that month was
    # never about, and the day would inherit the carry that follows -- the same
    # hazard `#materialize_to_time`'s own retry keeps clear of.
    ahead = spec[:year] > time.year || (spec[:year] == time.year && spec[:month] > time.month)

    if (spec[:month] != time.month || spec[:year] != time.year) &&
       !day_fits_month?(spec[:day], spec[:month], spec[:year], strict) &&
       (resized = month_start_like spec, (ahead ? time.at_beginning_of_day : time))
      refined = materialize_fields resized, carry, strict
      spec = refined if day_fits_month? refined[:day], refined[:month], refined[:year], strict
    end

    # Fields are fixed from the finest up, so each is chosen while the coarser
    # ones still hold the hint's values. When a coarser field then moves
    # forward, the finer *constrained* ones are free to start over from their
    # own earliest allowed value -- as picked they answer a question about a
    # time that has been left behind, and the earliest match gets stepped over.
    # Unconstrained fields keep what the hint gave them, which is what makes
    # this different from resetting wholesale.
    MAX_RESET_PASSES.times do
      advanced = highest_advanced_field time, spec
      break unless advanced

      restarted = restart_hint spec, advanced, time
      break unless restarted

      refined = materialize_fields restarted, carry, strict
      # A `#day` is sized by the month it lands in, and the restart hands the
      # pass a month of its own choosing -- January, where the year moved on.
      # Sizing it against the month the pass actually reached is what
      # `#materialize_to_time` does for the same reason; without it a rule
      # counting back from a month's end names a day that is out by one, the
      # refined spec reads as later than the first pass, and the restart is
      # thrown away along with the finer fields it was to reset.
      if refined[:month] != restarted.month
        resized = month_start_like refined, restarted
        refined = materialize_fields resized, carry, strict if resized
      end

      # A negative `#day` names a position counted back from a month's end, and
      # the first pass sized it by the hint's own month rather than the one it
      # landed in -- naming a day the rule does not allow there. Putting that
      # right is a correction rather than an improvement, so it is taken even
      # where it names a later day than the value it replaces.
      corrects = !day_fits_month?(spec[:day], spec[:month], spec[:year], strict) &&
                 day_fits_month?(refined[:day], refined[:month], refined[:year], strict)

      # Otherwise earlier than what the first pass found, and never earlier
      # than the hint itself -- starting the finer fields over is meant to stop
      # the earliest match being passed by, not to reach back before the
      # question asked.
      # A day the month cannot hold is not an improvement whatever the raw
      # integers say -- `-1` reads as earlier than the 1st and is no date at all
      break unless day_fits_month? refined[:day], refined[:month], refined[:year], strict
      break if !(earlier_spec?(refined, spec) || corrects) || earlier_spec?(refined, spec_of(time))

      spec = refined
    end

    spec
  end

  # Number of times `#materialize_with_hint` lets the finer fields start over.
  MAX_RESET_PASSES = 3

  private def materialize_fields(time : Time, carry, strict)
    _nanosecond, _second, _minute, _hour, carry = materialize_time_with_hint time, carry, strict
    _day, _month, _year, carry = materialize_date_with_hint time, carry, strict

    {year: _year, month: _month, day: _day, hour: _hour, minute: _minute, second: _second, nanosecond: _nanosecond}
  end

  # Returns the index of the coarsest field `spec` carried past the hint's own
  # value, or nil when none did. Fields run coarse to fine, year through
  # nanosecond.
  private def highest_advanced_field(hint : Time, spec) : Int32?
    {
      {hint.year, spec[:year]},
      {hint.month, spec[:month]},
      {hint.day, spec[:day]},
      {hint.hour, spec[:hour]},
      {hint.minute, spec[:minute]},
      {hint.second, spec[:second]},
      {hint.nanosecond, spec[:nanosecond]},
    }.each_with_index do |(hinted, produced), index|
      return index if produced > hinted
      return if produced < hinted
    end

    nil
  end

  # Returns a hint that keeps `spec` as far as `index` and sets every
  # constrained field finer than that to its own minimum, or nil when that
  # cannot be expressed as a `Time`.
  #
  # The coarse part comes from `spec` rather than from the hint: the field at
  # `index` is precisely the one that moved on, and anchoring the restart back
  # at the hint's value for it would undo the move -- landing before the hint
  # and being thrown away, restart and all.
  private def restart_hint(spec, index : Int32, hint : Time) : Time? # ameba:disable Metrics/CyclomaticComplexity
    year = spec[:year]
    month = index < 1 ? restart_value(self.month, spec[:month], hint.month, 1) : spec[:month]
    day = index < 2 ? restart_value(self.day, spec[:day], hint.day, 1) : spec[:day]
    hour = index < 3 ? restart_value(self.hour, spec[:hour], hint.hour, 0) : spec[:hour]
    minute = index < 4 ? restart_value(self.minute, spec[:minute], hint.minute, 0) : spec[:minute]
    second = index < 5 ? restart_value(self.second, spec[:second], hint.second, 0) : spec[:second]
    nanos =
      if index < 6 && nanosecond.nil? && millisecond.nil?
        hint.nanosecond
      elsif index < 6 && (restartable?(nanosecond) || restartable?(millisecond))
        0
      else
        spec[:nanosecond]
      end

    # Built in UTC whatever zone the search is in: this is read for its fields
    # and never as an instant, and a wall clock a DST gap swallowed would
    # otherwise come back from `Time.local` as a neighbouring one -- which the
    # restart would then read in, undoing itself and stepping over the earliest
    # match. A date the calendar does not hold at all is a different matter and
    # leaves the restart undone.
    Time.utc year, month, day, hour, minute, second, nanosecond: nanos
  rescue ArgumentError
    nil
  end

  # Returns the first of the month `spec` reached, carrying `like`'s time of
  # day, or nil where that wall clock does not exist.
  private def month_start_like(spec, like : Time) : Time?
    TimeHelper.local? spec[:year], spec[:month], 1, like.hour, like.minute, like.second,
      nanosecond: like.nanosecond, location: like.location
  end

  # Returns what a finer field starts over at once a coarser one has moved on.
  #
  # A constrained field goes back to the bottom of its range, `floor`, and is
  # materialized up again from there. An unconstrained one goes back to the
  # value the hint gave it: the only reason it holds anything else is a carry
  # raised to keep the answer at or after the hint, and a coarser field moving
  # forward has settled that question by itself. A `Proc` keeps what it has --
  # materialization has no way to bring one back up.
  private def restart_value(field, produced, hinted, floor)
    # A `Proc` counts as constrained here: `#materialize` asks it which values
    # it allows, so a field restarted to the bottom of its range is brought
    # back up to one it accepts, exactly as a list would be. Only the
    # nanosecond is too wide to ask about, and `#restart_hint` keeps that one
    # to itself.
    return floor unless field.nil?

    # The hint's own value, unless materialization reached this one by wrapping
    # past the end of the field -- December carrying into January, the 31st
    # into the 1st. Going back to the hint would then move the field *forward*,
    # naming a date the restart never meant and getting itself discarded for
    # being later than the pass it was refining.
    hinted > produced ? produced : hinted
  end

  # Returns whether a restart can put `value`'s field back at the bottom of its
  # range and trust materialization to bring it up to an allowed value again.
  #
  # A `Proc` cannot: `#materialize` hands the wanted value straight back for
  # one, so a field restarted to zero stays there -- and a rule the proc would
  # have accepted further up can then never be satisfied at all.
  @[AlwaysInline]
  private def restartable?(value) : Bool
    !value.nil? && !value.is_a?(VirtualProc)
  end

  # Returns `time`'s own fields in the shape a materialized spec has.
  private def spec_of(time : Time)
    {year: time.year, month: time.month, day: time.day, hour: time.hour,
     minute: time.minute, second: time.second, nanosecond: time.nanosecond}
  end

  # Returns whether `a` names an earlier moment than `b`, field by field.
  private def earlier_spec?(a, b) : Bool
    {a[:year], a[:month], a[:day], a[:hour], a[:minute], a[:second], a[:nanosecond]} <
      {b[:year], b[:month], b[:day], b[:hour], b[:minute], b[:second], b[:nanosecond]}
  end

  # Materializes date part of current VT
  def materialize_date_with_hint(time : Time = Time.local.at_beginning_of_minute, carry = 0, strict = true)
    _day, carry = materialize(day, time.day + carry, 1, TimeHelper.days_in_month(time) + 1, strict, variable_max: true)
    _month, carry = materialize(month, time.month + carry, 1, 13, strict)
    # Years are not cyclic the way the fields under them are: one carried past
    # the last the calendar holds has nowhere to wrap to, and letting it wrap
    # anyway answers a question about year 10000 with year 1 -- thousands of
    # years before the hint, which nothing asked for. A `#year` rule naming a
    # bygone year is a different matter, and still answers with it.
    if time.year + carry > 9999
      raise ArgumentError.new "no match at or after year #{time.year} exists within the calendar"
    end
    _year, carry = materialize(year, time.year + carry, 1, 10_000, strict)
    {_day, _month, _year, carry}
  end

  # Materializes time part of current VT
  # How many times a `#millisecond` and a `#nanosecond` rule are played off
  # against each other before the pair is taken as settled.
  MAX_SUBSECOND_PASSES = 4

  def materialize_time_with_hint(time : Time = Time.local.at_beginning_of_minute, carry = 0, strict = true)
    _nanosecond, carry = materialize(nanosecond, time.nanosecond + carry, 0, 1_000_000_000, strict)
    _nanosecond, carry = materialize_millisecond(_nanosecond, carry, strict)

    # Both name the same field of a `Time`, so folding the millisecond in can
    # name a nanosecond the nanosecond rule does not allow -- and the answer
    # then satisfies neither. Each pass only ever moves forward, so a few
    # settle the pair.
    unless nanosecond.nil? || millisecond.nil?
      MAX_SUBSECOND_PASSES.times do
        refined, refined_carry = materialize(nanosecond, _nanosecond, 0, 1_000_000_000, strict)
        break if refined == _nanosecond && refined_carry == 0

        _nanosecond = refined
        carry += refined_carry
        _nanosecond, carry = materialize_millisecond(_nanosecond, carry, strict)
      end
    end
    _second, carry = materialize(second, time.second + carry, 0, 60, strict)
    _minute, carry = materialize(minute, time.minute + carry, 0, 60, strict)
    _hour, carry = materialize(hour, time.hour + carry, 0, 24, strict)
    {_nanosecond, _second, _minute, _hour, carry}
  end

  # Folds a `#millisecond` requirement into an already-materialized nanosecond.
  #
  # A `Time` has no millisecond of its own -- `Time#millisecond` is just the
  # leading three digits of its nanosecond -- so a millisecond requirement can
  # only be met by choosing a suitable nanosecond. When the millisecond has to
  # move, the sub-millisecond remainder restarts at zero, the same way a
  # `#minute` that moves leaves the seconds behind it at zero.
  private def materialize_millisecond(_nanosecond : Int, carry : Int, strict : Bool)
    # `.nil?`, not truthiness: a `millisecond` of `false` is a rule that
    # matches nothing, and `#materialize` is the one that says so.
    return {_nanosecond, carry} if millisecond.nil?

    wanted = _nanosecond // 1_000_000
    value, ms_carry = materialize(millisecond, wanted, 0, 1_000, strict)

    return {_nanosecond, carry} if value == wanted && ms_carry == 0

    {value * 1_000_000, carry + ms_carry}
  end

  # Widest field a `Proc` is asked about value by value. Everything but the
  # nanosecond fits, and a second's worth of nanoseconds does not.
  MAX_PROC_SCAN = 100_000

  # Materializes a particular value with the help of a wanted/hint value.
  # If 'strict' is true and some of the `wanted` fields would not `match?` VT's requirements,
  # they are replaced/overriden with the first/earliest value from the allowed range.
  #
  # `variable_max` says the supplied `max` varies with the hint -- the length
  # of a month, the weeks of an ISO year, the days of a year. Only then can a
  # negative-bound value that adjusts to empty be empty *for this hint alone*,
  # and only then is the below-floor sentinel returned instead of raising;
  # a field with a fixed max (hour, minute, ...) that adjusts to empty is
  # empty for every hint and raises outright.
  def materialize(allowed, wanted : Int, min, max = nil, strict = true, variable_max = false) # ameba:disable Metrics/CyclomaticComplexity
    original = allowed
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
      if strict
        # Only the carry depends on `max` -- the replacement itself is what
        # `strict` asks for, the way the `Range` and `Enumerable` cases below
        # already do it regardless of `max`.
        carry += 1 if max && wanted > allowed
        wanted = allowed
      end
    in Range(Int32, Int32)
      adjust_wanted_re_max
      # Negatives are not resolved again here: `#adjust_value` above has
      # already done it, and doing it twice is not idempotent -- a `-31` sized
      # by a 29-day February comes back as `-2` and a second pass turns that
      # into 27, a day the rule never named. `#matches_adjusted?` keeps the two
      # sides apart for exactly this reason.
      # An empty range (e.g. `5...5`) permits nothing, so materializing it to
      # its `begin` would hand back a value the VirtualTime does not match.
      if RangeHelper.last(allowed).nil?
        # Unless it is empty only after adjustment against this hint's own
        # month or year length -- `day: -16..15` is empty in a 31-day month
        # yet holds the 15th in a 30-day one. Answer below the field's floor:
        # `day_fits_month?` and the week/day-of-year walks read that as
        # "nothing here" and move the search on, exactly as they do for an
        # Int the month cannot hold. A range born empty keeps raising.
        if variable_max && max && original.is_a?(Range(Int32, Int32)) && (original.begin < 0 || original.end < 0)
          return {min - 1, carry}
        end

        raise ArgumentError.new "A VirtualTime with empty range value `#{allowed}` isn't materializable."
      end
      if !strict || allowed.includes? wanted
      else
        carry += max && (wanted > allowed.begin) ? 1 : 0
        wanted = allowed.begin
      end
      # This covers Array(Int32) and Steppable::StepIterator(Int32,Int32,Int32)
    in Enumerable(Int32)
      adjust_wanted_re_max
      if allowed.is_a? Steppable::StepIterator(Int32, Int32, Int32)
        # A stepped range that yields nothing -- `#matches?` lets nothing
        # through for one either -- said before iterating it, since a step of
        # zero never reaches its limit
        smallest = RangeHelper.smallest allowed
        unless smallest
          # As with the empty-range case above: empty against this hint's own
          # month/year length is "nothing here", not "nothing anywhere".
          if variable_max && max && original.is_a?(Steppable::StepIterator(Int32, Int32, Int32)) &&
             (original.current < 0 || original.limit < 0)
            return {min - 1, carry}
          end

          raise ArgumentError.new "A VirtualTime with a stepped range value that yields nothing isn't materializable."
        end

        # Worked out from the bounds rather than by expanding them: a stepped
        # range over a second's worth of nanoseconds runs to hundreds of
        # millions of values, and building that list to pick one out of it
        # costs a gigabyte and several seconds.
        if strict && !RangeHelper.includes?(allowed, wanted)
          if candidate = RangeHelper.first_from allowed, wanted
            wanted = candidate
          else
            carry += max && (wanted > smallest) ? 1 : 0
            wanted = smallest
          end
        end

        return {wanted, carry}
      end

      allowed = allowed.to_a
      # A magnitude larger than the field itself -- `-9` for a day of the week,
      # `-117` for a second -- resolves to a value below the field's own floor,
      # one no date ever has. `#matches?` lets nothing through for one of those
      # while still honouring the values beside it, and materialization has to
      # do the same rather than hand back something `Time` will refuse. Values
      # above are a different matter: `max` for a `#day` is the length of the
      # *hint's* month, and a 31 asked about from April is not a nonsense day,
      # it is one the next month over has.
      allowed = allowed.select { |value| value >= min } if max
      # :ditto: for an empty list or a stepped range that yields no values
      if allowed.empty?
        # A list emptied by the floor-filter above -- `day: [-31]` sized by a
        # February -- is empty for this month only, like the ranges above; a
        # list born empty (or emptied for any other reason) keeps raising.
        if variable_max && max && (original.is_a?(Array(Int32)) || original.is_a?(Set(Int32))) && original.any?(&.<(0))
          return {min - 1, carry}
        end

        raise ArgumentError.new "A VirtualTime with an empty list of allowed values isn't materializable."
      end
      # The list arrives sorted: every `Array`/`Set` branch of `#adjust_value`
      # returns an ascending list, and the filter above preserves order.
      if !strict || allowed.includes? wanted
      else
        if candidate = allowed.find &.>=(wanted)
          wanted = candidate
        else
          carry += max && (wanted > allowed.min) ? 1 : 0
          wanted = allowed.min
        end
      end
    in VirtualProc
      adjust_wanted_re_max
      # A proc names the values it allows by answering about them, so the
      # earliest one at or after `wanted` is found by asking -- the same answer
      # the equivalent list would give, rather than leaving the field at
      # whatever the hint supplied and hoping a walk stumbles onto a match.
      # Nanoseconds are the one field too wide to ask about exhaustively.
      if strict && max && (max - min) <= MAX_PROC_SCAN
        found = (wanted...max).find { |candidate| allowed.call candidate }

        if found
          wanted = found
        elsif found = (min...wanted).find { |candidate| allowed.call candidate }
          carry += 1
          wanted = found
        end
      end
    end

    {wanted, carry}
  end

  # Comparison with self

  # Returns whether the two describe the same rule.
  #
  # `#location` and `#default_match?` count towards that: both decide which
  # `Time`s the object matches, so leaving them out would call two objects
  # equal that match disjoint sets of times -- and collapse them in a `Set`.
  def ==(other : self) # ameba:disable Metrics/CyclomaticComplexity
    (location == other.location) &&
      (default_match? == other.default_match?) &&
      (comparable(year) == comparable(other.year)) &&
      (comparable(month) == comparable(other.month)) &&
      (comparable(day) == comparable(other.day)) &&
      (comparable(week) == comparable(other.week)) &&
      (comparable(day_of_week) == comparable(other.day_of_week)) &&
      (comparable(day_of_year) == comparable(other.day_of_year)) &&
      (comparable(hour) == comparable(other.hour)) &&
      (comparable(minute) == comparable(other.minute)) &&
      (comparable(second) == comparable(other.second)) &&
      (comparable(millisecond) == comparable(other.millisecond)) &&
      (comparable(nanosecond) == comparable(other.nanosecond))
  end

  # Returns a stand-in for `value` that two equal rules share.
  #
  # A stepped range is a `Steppable::StepIterator` -- a reference type with no
  # equality of its own -- so two rules written from the same literal would
  # otherwise compare unequal and take two slots in a `Set` meant to dedupe
  # them. Its bounds, step and exclusivity describe it exactly and are read in
  # constant time, unlike expanding it, which for a range of nanoseconds is a
  # billion values.
  private def comparable(value)
    case value
    when Steppable::StepIterator(Int32, Int32, Int32)
      {value.current, value.limit, value.step, value.exclusive}
    when Array(Int32), Set(Int32)
      # A list of allowed values is the same rule whatever order it is written
      # in and whichever of the two containers holds it -- matching reads both
      # the same way, and YAML has no syntax that tells them apart, so a rule
      # that has been through it would otherwise stop equalling itself.
      # A one-element list is likewise the same rule as its scalar -- YAML
      # writes `[5]` as `5` and reads an `Int32` back -- so it compares (and
      # hashes) as the Int.
      list = value.to_a.sort
      list.size == 1 ? list.first : list
    else
      value
    end
  end

  # Hashes the same fields `#==` compares, so that two `VirtualTime`s that
  # compare equal also land in the same `Hash` bucket and dedupe in a `Set`.
  def hash(hasher)
    hasher = @location.hash hasher
    hasher = @default_match.hash hasher
    {% for field in FIELDS %}
      hasher = comparable(@{{ field.id }}).hash hasher
    {% end %}
    hasher
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
  # specific point in time, so `<` and `>` are always `false`, and `<=` and
  # `>=` are true exactly when the time matches (`Comparable` semantics for an
  # undefined ordering, where the only defined outcome is "equal").
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

  # Returns `time` moved by whole days, keeping its time of day.
  #
  # Adding a `Time::Span` would instead add an exact duration, which shifts the
  # wall clock by an hour whenever the span crosses a DST transition -- enough
  # to move the result out of an `#hour` or `#minute` the VirtualTime requires.
  @[AlwaysInline]
  private def shift_days(time : Time, span : Time::Span) : Time
    days = span.days
    # Shifting by nothing is not a no-op to `Time#shift`: it rebuilds the value
    # from its wall clock, and across a DST fall-back an ambiguous wall clock
    # resolves to the first of its two occurrences -- quietly moving the instant
    # an hour earlier.
    return time if days == 0

    shifted = time.shift days: days
    # The wall clock being aimed for may not exist on the day landed on -- a
    # DST forward transition skipped it -- and `Time#shift` then resolves it to
    # a neighbouring one, which depending on the zone can even read as the day
    # before. Neither is the day the walk asked for. What that day does hold at
    # or after the missing clock is the instant the gap ends.
    return shifted if shifted.hour == time.hour && shifted.minute == time.minute &&
                      shifted.second == time.second && shifted.nanosecond == time.nanosecond

    gap_end_near(shifted) || shifted
  end

  # Converts a VirtualTime to a specific Time object that matches the VirtualTime.
  #
  # Value is converted using a time hint, which defaults to the current time.
  # Lists and ranges of values materialize to their min / begin value.
  #
  # Additionally, any requirements for week number, day of week, and day of year are also met,
  # possibly by doing multiple iterations to find a suitable date. The process is limited to
  # some max attempts of trying to find a value that simultaneously satisfies all constraints.
  def to_time(hint = Time.local.at_beginning_of_minute, strict = true) # ameba:disable Metrics/CyclomaticComplexity
    # The field values are expressed in the VirtualTime's own location, so that
    # is where they have to be materialized; `#matches?` converts the time it is
    # given the same way round. Without a location of its own, the hint's zone
    # is used and propagates to the result.
    if (loc = location) && hint.location != loc
      hint = hint.in loc
    end

    time = materialize_to_time hint, strict

    # The time of day the hint itself asks for, kept aside for the walks below.
    # Materialization can be driven off it -- a date that cannot hold the wall
    # clock, or one the day/month rules reject, sends it looking from somewhere
    # else -- and what it settles on then answers a question about a date the
    # walk is about to leave behind.
    wanted = begin
      materialize_spec hint, strict: strict
    rescue ArgumentError
      spec_of time
    end

    # An unconstrained field is filled from the hint, and materialization may
    # have carried that value forward to keep the answer at or after the hint
    # -- an hour of 8 reported as 9 because the minute had to move back. Once a
    # walk has moved onto a later date the carry is spent, so what the field
    # starts over at is whichever of the two clocks is the earlier. Per field,
    # since a carry that wrapped leaves the smaller value on the other side.
    wanted = {
      year:       wanted[:year],
      month:      wanted[:month],
      day:        wanted[:day],
      hour:       {wanted[:hour], hint.hour}.min,
      minute:     {wanted[:minute], hint.minute}.min,
      second:     {wanted[:second], hint.second}.min,
      nanosecond: {wanted[:nanosecond], hint.nanosecond}.min,
    }

    # A `#week`, `#day_of_week` or `#day_of_year` rule is what settles the
    # date; the month and day materialization supplied are only where the walk
    # into it starts from. Where a coarser field has moved past the hint -- a
    # `#year` the hint was behind, a `#month` it had already gone by -- the
    # hint's own month and day answer a question about a unit left behind, and
    # walking forward from them steps over every date in the new one that would
    # have matched. Sometimes over all of them: a walk that runs off the end of
    # a pinned year has nowhere left to land.
    if week || day_of_week || day_of_year
      restarted = restart_date time, hint, wanted, strict
      time = restarted if restarted && hint <= restarted < time
    end

    max_tries = 100
    tries = 0
    finder = nil
    year_restarted = false
    year_restarts = 0

    # Under `strict: false` the time of day is the hint's own and answers to
    # nothing, while the date still has to satisfy the rule -- so the date is
    # asked about on its own, and strictly. Doing it here rather than leaving
    # it to the retry below keeps the answer on the same date `strict: true`
    # would have reached: the loop would otherwise reject the hint's own date
    # and start looking from the day after it.
    unless strict
      dated = (finder = date_only).to_time day_start(hint) || hint, true
      # Not guarded on being at or after the hint: a `#year` naming only bygone
      # years has nowhere else to go, and `#to_time` answers in the past for it
      # either way -- refusing that answer here only sends the loop crawling
      # forward from a date it has already found.
      time = with_time_of_day(dated, hint) || dated
    end

    loop do
      tries += 1
      walked_from = time

      # Anchor deterministically using ISO week rules.
      #
      # The date is settled strictly whatever `strict` says: the loop breaks
      # only for a date `#matches_date?` accepts, so a walk that leaves the
      # value where it found it -- which is all a loose materialization does --
      # has nothing to offer but a day-by-day crawl towards a date it could
      # have named outright. `strict` governs the time of day, which
      # `#matches_time?` is asked about only when it is set.
      week_nr = week ? time.calendar_week[1] : nil
      target_week = week_nr ? materialize(week, week_nr, 0, TimeHelper.weeks_in_year(time) + 1, true, variable_max: true)[0] : nil

      if target_week && week_nr != target_week
        # Not in the wanted week yet: land on it, on the wanted day if there is
        # one and on its first day otherwise. The wanted day is taken from the
        # start of the week rather than from the hint's own day of week -- once
        # the search has moved to a different week, the day the hint happened to
        # fall on says nothing, and letting it in would step over the earlier
        # allowed days of the week it moved to.
        target_dow = day_of_week ? materialize(day_of_week, 1, 1, 8, true)[0] : 1
        time = anchor_to_iso_week time, target_dow - 1, true
      elsif day_of_week
        # Already in the wanted week (or there is no week rule), so walk
        # forward to the wanted day of week. Anchoring here instead would go
        # back to the week's own Monday, and `#anchor_to_iso_week` would then
        # have to skip a whole year to stay in the future -- passing over every
        # matching date in between.
        current_dow = time.day_of_week.to_i
        value, _ = materialize(day_of_week, current_dow, 1, 8, true)
        time = shift_days time, adjust_day(current_dow, value, 7)
      end

      current_doy = time.day_of_year
      days_this_year = TimeHelper.days_in_year time
      value, carry = materialize(day_of_year, current_doy, 1, days_this_year + 1, true, variable_max: true)

      if (value < current_doy || carry != 0) && time.year < 9999
        # The wanted day lies in the year after this one, and the two need not
        # be the same length: a negative day of year counts back from the end,
        # so it is one day out for every leap year crossed. It is resolved
        # again, from the start of the year actually being landed in.
        value, _ = materialize(day_of_year, 1, 1, Time.days_in_year(time.year + 1) + 1, true, variable_max: true)
        time = shift_days time, ((days_this_year - current_doy) + value).days
      else
        time = shift_days time, adjust_day(current_doy, value, days_this_year)
      end

      # The walks move the date while keeping the time of day that was settled
      # on for the date they started from -- where a constrained field can have
      # been pushed past its own earliest allowed value by the hint, and where
      # an unconstrained one can have been moved off the hint's value by a date
      # that could not hold it. Both start over on a date reached later.
      if time.year != walked_from.year || time.month != walked_from.month || time.day != walked_from.day
        restarted = restart_time_of_day time, wanted, strict
        time = restarted if restarted >= hint
      end

      # The walks above rebuild the value from its wall clock, and one that a
      # DST fall-back repeats comes back as the later of its two occurrences.
      # Prefer the earlier while it is still at or after the hint, the way
      # materialization does -- otherwise the first of the two is never seen.
      time = prefer_earlier_fold time, hint

      # `matches_time?` catches a day walk that landed the materialized time of
      # day on a date where it does not exist, i.e. inside a DST gap. Under
      # `strict: false` the time of day is the hint's own and is not expected to
      # satisfy the VirtualTime in the first place.
      if matches_date?(time) && (!strict || matches_time?(time))
        break if time >= hint || year.nil? || year_restarts >= MAX_YEAR_RESTARTS

        # An answer before the hint is right only where the rule has no year
        # left at or after it -- a `#year` naming solely bygone years. Where it
        # does have one, the walk starts again there rather than settling for a
        # date the caller has already gone past.
        following =
          begin
            # Which years the rule allows is not a question `strict` has any
            # say over: it governs the time of day
            value, carried = materialize year, time.year + 1, 1, 10_000, true
            carried == 0 ? value : nil
          rescue ArgumentError
            nil
          end

        january = following ? january_of_year(following, time) : nil
        break unless january

        year_restarts += 1
        time = january
        next
      end

      if tries >= max_tries
        # TODO maybe some other error, not arg err
        raise ArgumentError.new "Could not find a Time that satisfies all of #{inspect} after #{max_tries} iterations (reached #{time})"
      end

      # It didn't match, so retry from the next day. The day is re-materialized
      # rather than merely incremented, so that the year/month/day constraints
      # snap forward to their next allowed combination in one go; crawling day
      # by day would exhaust `max_tries` long before reaching e.g. the next
      # December 25 that falls on a Friday.
      #
      # The next day is asked about from the earliest time of day the rule
      # allows on it, not from whatever the walk was carrying: an hour the
      # current date could not hold -- a DST gap sees to that -- would
      # otherwise become a floor on every date tried afterwards.
      # A `#year` that cannot move has no room for a walk that ran off the end
      # of it: the walk goes forward into the next year, the year rule pulls
      # the date back, and the search alternates between the same two dates
      # until its attempts run out. What it needs is to walk the year again
      # from its start -- tried once, and only where the walk has left the
      # years the rule allows, which is exactly when an answer earlier in the
      # year is the only one there can be.
      if !year.nil? && !year_restarted && (week || day_of_week || day_of_year) &&
         !matches?(year, time.year, 10_000)
        year_restarted = true
        january = january_of walked_from

        if january
          time = january
          next
        end
      end

      # A `#nanosecond` proc is the one `#materialize` cannot pick a value for,
      # and moving a whole day on would meet the same clock again -- so the
      # walk goes by the unit the field measures instead. Only where the date
      # already suits, though: a minute at a time is no way to reach the next
      # allowed *date*, and the attempts run out inside two hours.
      if (step = proc_step) && matches_date?(time)
        time += step
        next
      end

      next_day = shift_days time, 1.day

      if strict
        time = earliest_materialization restart_time_of_day(next_day, wanted, strict), strict
      else
        # Under `strict: false` the time of day is the hint's own and is not
        # asked to satisfy anything -- but the date still is, since the loop
        # settles only for one `#matches_date?` accepts. So the date is what
        # gets asked about, on its own and strictly: asking loosely leaves
        # nothing to snap it forward and the search degenerates into a
        # day-by-day crawl, while asking strictly for the whole rule drags the
        # time of day back in -- an `hour` a DST gap swallowed on the date
        # wanted would send the answer to another month entirely.
        dated = (finder ||= date_only).to_time day_start(next_day) || next_day, true
        time = with_time_of_day(dated, hint) || dated
      end
    end

    time
  end

  # Returns the start of the coarsest date unit `time` has moved on to past the
  # hint -- the year where the year itself advanced, the month otherwise --
  # materialized afresh, or nil where nothing moved.
  private def restart_date(time : Time, hint : Time, wanted, strict : Bool) : Time?
    month =
      if time.year > hint.year
        1
      elsif time.year == hint.year && time.month > hint.month
        time.month
      else
        return
      end

    start = TimeHelper.local? time.year, month, 1, time.hour, time.minute, time.second,
      nanosecond: time.nanosecond, location: time.location
    return unless start

    earliest_materialization restart_time_of_day(start, wanted, strict), strict
  rescue ArgumentError
    nil
  end

  # How many times `#to_time` starts the walk again in a later year the rule
  # allows, when the year it was in only holds matches behind the hint.
  MAX_YEAR_RESTARTS = 3

  # Returns the first instant of `time`'s own year, keeping its time of day, or
  # nil where that wall clock does not exist there.
  private def january_of(time : Time) : Time?
    january_of_year time.year, time
  end

  # :ditto: for a year of one's own choosing.
  private def january_of_year(year : Int32, time : Time) : Time?
    TimeHelper.local? year, 1, 1, time.hour, time.minute, time.second,
      nanosecond: time.nanosecond, location: time.location
  end

  # Returns how far the retry moves on when a time-of-day field is a `Proc`:
  # the unit that field measures, since `#materialize` cannot pick a value for
  # one and only a walk can reach it. A `#nanosecond` proc has no usable step
  # -- a walk of nanoseconds reaches nowhere -- and falls back to the date.
  private def proc_step : Time::Span?
    return 1.second if second.is_a?(VirtualProc)
    return 1.minute if minute.is_a?(VirtualProc)
    return 1.hour if hour.is_a?(VirtualProc)

    nil
  end

  # Returns a copy of this rule carrying only its date fields.
  #
  # Under `strict: false` the time of day is the hint's own and answers to
  # nothing, while the date still has to satisfy the rule. Dropping the time of
  # day is what lets the date be asked about strictly without it being dragged
  # along.
  private def date_only : VirtualTime
    copy = self.class.new
    copy.year = year
    copy.month = month
    copy.day = day
    copy.week = week
    copy.day_of_week = day_of_week
    copy.day_of_year = day_of_year
    copy.location = location
    copy.default_match = default_match?
    copy
  end

  # Returns the first instant of `time`'s own day, or nil where a DST gap
  # swallowed it.
  private def day_start(time : Time) : Time?
    TimeHelper.local? time.year, time.month, time.day, location: time.location
  end

  # Returns `time`'s date carrying `clock`'s time of day, or nil where that
  # wall clock does not exist on it.
  private def with_time_of_day(time : Time, clock : Time) : Time?
    TimeHelper.local? time.year, time.month, time.day, clock.hour, clock.minute, clock.second,
      nanosecond: clock.nanosecond, location: time.location
  end

  # Returns `time` with its time of day started over: every constrained field
  # back at the earliest value it allows, every unconstrained one back at what
  # the hint asked for.
  #
  # The date walks settle the time of day against one date and then move to
  # another, where an `hour` of `[3, 9]` that had to take 9 for a hint at 08:40
  # can have 3 again. Where the earliest the rule allows does not exist on the
  # date -- a DST gap -- the date holds nothing before the gap ends. A time of
  # day later than the one already in hand is no improvement and is dropped.
  private def restart_time_of_day(time : Time, wanted, strict : Bool) : Time # ameba:disable Metrics/CyclomaticComplexity
    # Only the time-of-day fields of the hint are read, and all of them are
    # zero on the first pass: the point is to start each constrained field
    # from the bottom. A pass that names a wall clock the date does not hold
    # tries again from where the gap ends, which is that date's own floor --
    # answering with the gap end itself would hand back a time of day the rule
    # never asked for, and abandoning the date would step over the matches it
    # still has later on.
    probe = Time.utc 2000, 1, 1

    3.times do |pass|
      _nanosecond, _second, _minute, _hour, carry = materialize_time_with_hint probe, 0, strict
      return time unless carry == 0

      if pass.zero?
        _hour = wanted[:hour] if hour.nil?
        _minute = wanted[:minute] if minute.nil?
        _second = wanted[:second] if second.nil?
        _nanosecond = wanted[:nanosecond] if nanosecond.nil? && millisecond.nil?
      end

      # A nanosecond a proc decides is the one field materialization cannot
      # start over for -- it is too wide to ask about value by value -- so it
      # keeps what it was already given.
      _nanosecond = time.nanosecond if nanosecond.is_a?(VirtualProc)

      candidate = Time.local time.year, time.month, time.day, _hour, _minute, _second,
        nanosecond: _nanosecond, location: time.location

      if candidate.day == time.day && candidate.hour == _hour &&
         candidate.minute == _minute && candidate.second == _second
        # Later than what is already in hand is normally no improvement -- but
        # a `time` that does not satisfy the rule at all is no answer either,
        # and where a gap has left the walk standing on one, the date's own
        # first matching time of day is what it was looking for.
        return candidate if candidate < time || (strict && !matches_time?(time))

        return time
      end

      resolved = gap_end_near candidate
      return time unless resolved && resolved.day == time.day

      probe = resolved
    end

    time
  rescue ArgumentError
    time
  end

  # Returns `time` moved onto day `day_offset` (0 for Monday) of the ISO week
  # `#week` asks for, keeping its time of day.
  #
  # The anchor is a position within an ISO year, and the wanted week of the
  # year `time` falls in may well be behind it already (e.g. week 10 when
  # `time` is in May). Since materialization only ever moves forward, a
  # following year's anchor is used in that case.
  #
  # The week is resolved once per year tried, not once for the year `time`
  # started in: a negative week counts back from the end of an ISO year, and
  # those have either 52 weeks or 53. Resolving it against one year and landing
  # in another would put the answer a week out -- and `#matches_date?`, which
  # resolves against the year it is handed, would then turn it down.
  private def anchor_to_iso_week(time : Time, day_offset : Int, strict : Bool) : Time
    year = time.calendar_week[0]

    # An anchor a year later is (nearly) a year in the future, so at most a
    # couple of them can precede `time`.
    3.times do |attempt|
      # ISO week 1 is the week containing Jan 4
      jan4 = Time.local(year, 1, 4, location: time.location)
      week1_monday = jan4.shift days: -(jan4.day_of_week.to_i - 1)
      # Only the year `time` is already in has a week to stay ahead of. Asking
      # about a later one from `time`'s own week number would step over every
      # allowed week before it -- which is exactly what a list holding a
      # negative week does, that resolving to 52 in one year and 53 in the next.
      from_week = attempt.zero? ? time.calendar_week[1] : 1
      target_week, _ = materialize(week, from_week, 0, TimeHelper.weeks_in_iso_year(year, time.location) + 1, strict, variable_max: true)
      # Walk days with calendar arithmetic and rebuild the value with the
      # already-materialized time-of-day, so that neither the walk itself
      # nor DST transitions disturb the time part.
      date = week1_monday.shift days: (target_week - 1) * 7 + day_offset
      candidate = Time.local(date.year, date.month, date.day, time.hour, time.minute, time.second, nanosecond: time.nanosecond, location: time.location)

      return candidate if candidate >= time

      year += 1
    end

    # Every anchor tried lies in the past; leave `time` alone and let the caller
    # advance it.
    time
  end

  # Number of hints `#materialize_to_time` tries before giving up on finding a
  # month in which the materialized date exists.
  MAX_MATERIALIZE_TRIES = 100

  # Materializes `self` into a `Time`, ignoring the week number, day of week,
  # and day of year constraints (which `#to_time` goes on to satisfy).
  #
  # A `day` is sized by the month it ends up in -- `-1` is the last day of the
  # month, and `31` exists only in 31-day months -- yet the month is itself
  # known only after the day has been materialized and its carry applied. A
  # pass therefore sizes the day by the *hint's* month, and can both name a
  # date that does not exist (February 31) and, for a rule counting from the
  # end of a month, name the wrong day of a perfectly real one (`-2` is the
  # 30th of January but the 27th of February). Either way the hint is moved
  # onto the month that pass arrived at and the materialization is repeated
  # with the day sized by that month; if the day does not fit there either, the
  # search moves on to the next month.
  #
  # A time of day can be missing from a date in the same way: a DST forward
  # transition leaves a gap of local times that never occur, and `Time.local`
  # silently resolves those to a neighbouring instant whose fields are no
  # longer the ones materialized. Those retry from just past the gap.
  private def materialize_to_time(hint : Time, strict : Bool) : Time # ameba:disable Metrics/CyclomaticComplexity
    original_hint = hint
    tries = 0

    loop do
      timespec = materialize_spec hint, strict: strict
      _year, _month, _day = timespec[:year], timespec[:month], timespec[:day]

      # A year or month outside `Time`'s own range is not something another
      # hint could fix, so it is passed on to `Time.local` to report.
      if !((1..9999).includes?(_year) && (1..12).includes?(_month)) || day_fits_month?(_day, _month, _year, strict)
        time = Time.local **timespec, location: hint.location

        if exists_as_local?(time, timespec)
          # A DST fall-back makes a local time occur twice, and `Time.local`
          # settles on one of the two without saying which. The step between
          # them is whatever offset the zone gave up, which need not be an
          # hour -- Lord Howe gives up thirty minutes. Prefer the earlier
          # occurrence while it is still at or after the hint, since otherwise
          # the first of the two is skipped, and fall forward to the later one
          # when the chosen instant is behind the hint, which would otherwise
          # answer with a `Time` before the one asked about.
          fold = TimeHelper.dst_fold_at time

          if fold > Time::Span.zero
            earlier = time - fold
            time = earlier if earlier >= hint && exists_as_local?(earlier, timespec)

            if time < hint
              later = time + fold
              time = later if later >= hint && exists_as_local?(later, timespec)
            end
          end

          return time
        end

        tries += 1
        raise ArgumentError.new "no time of day matching #{timespec} exists in #{MAX_MATERIALIZE_TRIES} attempts" if tries >= MAX_MATERIALIZE_TRIES

        # The wanted local time does not exist -- a DST forward transition
        # skipped over it. Retry from the instant the gap ends, which is the
        # first local time after it: `Time.local` resolves such a wall clock to
        # one side of the gap or the other depending on the zone, and retrying
        # from there would carry that side's own time of day into the next
        # pass, stepping over the matches that sit just past the gap.
        resolved = gap_end_near(time) || (time > hint ? time : time + 1.hour)
        hint = resolved > hint ? resolved : hint + 1.hour
        next
      end

      tries += 1
      if tries >= MAX_MATERIALIZE_TRIES
        raise ArgumentError.new "no month in which day #{_day} is the wanted one was found in #{MAX_MATERIALIZE_TRIES} attempts"
      end

      first_of_month = Time.local(_year, _month, 1, hint.hour, hint.minute, hint.second,
        nanosecond: hint.nanosecond, location: hint.location)
      # Re-sizing the day by the month this pass reached is what the retry is
      # for, and that month need not be a later one than the hint's own: a
      # `#year` and `#month` both pinned to a month already gone by have
      # nowhere later to be re-sized in, and moving on by a month would leave
      # the pinned pair for good -- landing back on the same spec every time
      # until the attempts ran out. Only a pass that stayed in the hint's own
      # month has nothing to re-size and has to move on.
      hint =
        if _month == hint.month && _year == hint.year
          # Moving on to a later month, where the hint's own clock has nothing
          # left to say: carrying it there would floor every constrained
          # time-of-day field at it in a month it was never about, and the day
          # would inherit the carry that follows -- stepping over a whole
          # month of matches, or oscillating between two months for good.
          moved = first_of_month.shift months: 1
          Time.local moved.year, moved.month, 1, location: hint.location
        else
          first_of_month
        end
    end
  rescue e : ArgumentError
    raise ArgumentError.new "#{inspect} with hint #{original_hint} could not be materialized into a Time (#{e.message})"
  end

  # Returns whether `_day` exists in the given month and is what `#day` asks
  # for once sized by it.
  @[AlwaysInline]
  private def day_fits_month?(_day : Int, _month : Int, _year : Int, strict : Bool) : Bool
    days = Time.days_in_month _year, _month
    return false unless (1..days).includes? _day
    # A nil `day` accepts whatever the hint supplied; asking `#matches?` would
    # consult `#default_match?`, which has no say over an unconstrained field
    # that materialization has already filled in. Under `strict: false` the day
    # is the hint's own and is not expected to satisfy the rule either -- only
    # that the month holds it matters, and `#to_time`'s own walk goes on to
    # find a date that does.
    # A `Proc` cannot be materialized to either: `#materialize` hands the
    # wanted value straight back, so insisting the day satisfy one here leaves
    # the search hopping months that all offer the same first day. `#to_time`'s
    # own walk asks `#matches_date?`, proc and all, and reaches it a day at a
    # time.
    !strict || day.nil? || day.is_a?(VirtualProc) || matches?(day, _day, days + 1)
  end

  # Returns the earliest materialization at or after `hint`, re-asking from the
  # start of the day, month and year the first answer landed in.
  #
  # The week, day of week and day of year walks leave the search on a date that
  # may no longer suit the year/month/day rules, and materializing again from
  # the day after keeps that date's own day of the month. Where a coarser field
  # then has to move, the day left over can carry the answer past every date
  # that would have matched -- and go on doing so, a year at a time, until the
  # attempts run out on a rule that is perfectly satisfiable.
  private def earliest_materialization(hint : Time, strict : Bool) : Time
    seeds = ->(best : Time) { unit_starts best, hint }

    TimeHelper.refine_earliest materialize_to_time(hint, strict), hint, MAX_RESET_PASSES, seeds do |seed|
      materialize_to_time seed, strict
    rescue ArgumentError
      nil
    end
  end

  # Returns the starts of the day, month and year `time` falls in, dropping any
  # that would reach back before `floor`.
  private def unit_starts(time : Time, floor : Time) : Array(Time)
    location = time.location

    [
      Time.local(time.year, time.month, time.day, 0, 0, 0, location: location),
      Time.local(time.year, time.month, 1, 0, 0, 0, location: location),
      Time.local(time.year, 1, 1, 0, 0, 0, location: location),
    ].select &.>=(floor)
  end

  # Returns the instant at which a DST gap around `resolved` ends, or nil when
  # no forward transition is found within a couple of hours either side.
  private def gap_end_near(resolved : Time) : Time?
    # A couple of hours either side covers an ordinary spring-forward, and
    # looking no further than that keeps an unrelated transition from being
    # mistaken for this one. A gap can be far wider though -- Samoa skipped a
    # whole day moving across the date line -- so a second, wider look follows
    # when the near one finds nothing.
    {2.hours, 26.hours}.each do |reach|
      before = resolved - reach
      after = resolved + reach
      next unless before.offset < after.offset

      found = TimeHelper.transition_between before, after
      return found if found
    end

    nil
  rescue ArgumentError
    # Too near the end of the representable calendar to look either way
    nil
  end

  # Returns the earlier of the two instants sharing `time`'s wall clock where a
  # DST fall-back repeats it, provided that one is still at or after `floor`.
  private def prefer_earlier_fold(time : Time, floor : Time) : Time
    fold = TimeHelper.dst_fold_at time
    return time unless fold > Time::Span.zero

    earlier = time - fold
    return time unless earlier >= floor
    return time unless TimeHelper.same_wall_clock? earlier, time

    earlier
  end

  # Returns whether `time` really carries the date and time `timespec` asked
  # for, i.e. whether that local time exists in `time`'s location at all.
  @[AlwaysInline]
  private def exists_as_local?(time : Time, timespec) : Bool
    time.year == timespec[:year] && time.month == timespec[:month] && time.day == timespec[:day] &&
      time.hour == timespec[:hour] && time.minute == timespec[:minute] && time.second == timespec[:second]
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

  # Sets all VT fields, `#location` included, to nil
  def clear!
    clear_date!
    clear_time!
    self.location = nil
    self
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
  #
  # `#location` is left alone: it converts the whole timestamp before matching,
  # so it bears on the date as much as on the time of day, and dropping it here
  # would quietly change what `#matches_date?` answers. `#clear!` resets it.
  def clear_time!
    self.hour = nil
    self.minute = nil
    self.second = nil
    self.millisecond = nil
    self.nanosecond = nil
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
  #
  # `#default_match?` is carried over, since without it the expansion of a VT
  # that matches nothing would be a set of VTs that match nearly everything.
  def expand
    ArrayHelper.expand(VTTuple.new year, month, day, week, day_of_week, day_of_year, hour, minute, second, millisecond, nanosecond, location)
      .map { |v| self.class.new *(VTTuple.from v), default_match: default_match? }
  end

  # Iterator-related stuff

  # Produces closest-next `Time` that matches the current VT, starting with `from` + 1 nanosecond onwards.
  # (Because it always finds the "next" time, the default value is `at_end_of_minute` (:99).)
  def succ(from : Time = Time.local.at_end_of_minute)
    time = to_time from + 1.nanosecond

    # A DST fall-back repeats a stretch of wall clock: every instant in
    # `[transition, transition + fold)` reads as a wall clock that already
    # happened `fold` earlier. Materialization works in wall-clock fields, so
    # it only ever sees each of those once and steps over the repeat entirely.
    # Find the earliest match inside it by searching the first pass and mapping
    # the hit forward. A positive difference is what marks a fall-back; the
    # step comes from the offsets themselves rather than being assumed to be an
    # hour, since Lord Howe shifts by thirty minutes.
    # Whether a fall-back is in play is settled by looking around `from`, not
    # by comparing offsets with the answer: materialization can land a year
    # away, and the span between would then hold several transitions -- none of
    # them the one that matters.
    if (fold = TimeHelper.dst_fold_at from) > Time::Span.zero
      repeated = repeat_of_fold from, time, fold
      time = repeated if repeated
    end

    # `#to_time` may legitimately answer with a time in the past -- a rule
    # pinned to a bygone year has nowhere else to go -- but a *successor* that
    # is not after `from` is no successor at all, and an iterator built on one
    # would hand back the same value for ever.
    if time <= from
      raise ArgumentError.new "#{inspect} has no match after #{from} (materialized to #{time})"
    end

    time
  end

  # Returns the earliest match inside a DST fall-back's repeated stretch of
  # wall clock, or `nil` when there is none worth preferring to `time`.
  #
  # Every instant in `[transition, transition + fold)` reads as a wall clock
  # that already happened `fold` earlier. Materialization works in wall-clock
  # fields, so it meets each of those once and steps over the repeat entirely;
  # searching the earlier stretch and carrying the hit forward reaches it.
  private def repeat_of_fold(from : Time, time : Time, fold : Time::Span) : Time?
    transition = TimeHelper.transition_between from - 2.hours, from + 2.hours
    return unless transition

    # Start where `from` itself falls in the earlier stretch, so the match
    # found is the first one that is genuinely after it
    lower = {from + 1.nanosecond, transition}.max
    first_pass = to_time lower - fold
    return unless first_pass < transition

    repeated = first_pass + fold
    return unless from < repeated < time

    matches?(repeated) ? repeated : nil
  rescue ArgumentError
    # The earlier stretch holds no match of its own
    nil
  end

  # Returns Iterator
  #
  # `interval` is how far past the last match the search for the next one
  # resumes, and `by` is how many matches each `#next` advances by. Both have
  # to be positive: a zero `interval` or `by` would make the iterator hand back
  # the same `Time` forever, and a negative `interval` would walk backwards.
  def step(interval = 1.minute, by = 1, from = Time.local.at_end_of_minute) : Iterator
    raise ArgumentError.new "Step interval must be positive, got #{interval}" unless interval > Time::Span.zero
    raise ArgumentError.new "Step `by` must be positive, got #{by}" unless by > 0

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
        previous = @current
        @current = @virtualtime.succ @current + @interval - 1.nanosecond
        # An iterator that does not advance would yield the same `Time` for
        # ever; treat standing still as the end of the sequence.
        @reached_end = true if @current <= previous
      rescue ArgumentError
        # No further Time satisfies the VT's constraints
        @reached_end = true
      end

      @reached_end ? stop : @current
    end
  end

  # Helper methods below

  module TimeHelper
    # Returns the number of weeks -- 52 or 53 -- in the given ISO year.
    #
    # A year has 53 weeks when it begins on a Thursday, or when it is a leap
    # year beginning on a Wednesday. 2020 was such a year.
    def self.weeks_in_iso_year(year : Int, location : Time::Location) : Int32
      # December 28 is always in the last ISO week of its own year
      Time.local(year, 12, 28, location: location).calendar_week[1]
    end

    # Returns the number of weeks (52 or 53) in the ISO year that `time` falls in.
    #
    # Note that this is the ISO year, which is what `Time#calendar_week` (and
    # therefore `.week`) counts weeks within: the first days of January can
    # still belong to the previous ISO year, and the last days of December to
    # the next one.
    def self.weeks_in_year(time : Time)
      weeks_in_iso_year time.calendar_week[0], time.location
    end

    # :nodoc:
    def self.weeks_in_year(time : VirtualTime)
      0
    end

    # Returns number of days in month of specified `time`
    def self.days_in_month(time : Time)
      Time.days_in_month time.year, time.month
    end

    # :ditto:
    def self.days_in_month(time : VirtualTime)
      0
    end

    # Returns ISO week number (1..53) of specified `time`
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

    # Returns whether the two carry the same wall clock, whatever offset each
    # reads it with.
    def self.same_wall_clock?(a : Time, b : Time) : Bool
      a.year == b.year && a.month == b.month && a.day == b.day &&
        a.hour == b.hour && a.minute == b.minute && a.second == b.second &&
        a.nanosecond == b.nanosecond
    end

    # Returns a `Time` carrying exactly the wall clock asked for, or nil where
    # that wall clock does not exist.
    #
    # A DST forward transition leaves a gap of local times that never occur,
    # and `Time.local` silently resolves one of those to a neighbouring instant
    # whose fields are no longer the ones asked for -- which in some zones even
    # reads as the day before. A date the calendar does not hold at all (the
    # 30th of February) is refused by `Time.local` outright, and answers nil
    # just the same.
    def self.local?(year : Int, month : Int, day : Int, hour : Int = 0, minute : Int = 0, second : Int = 0, *, nanosecond : Int = 0, location : Time::Location) : Time?
      time = Time.local year, month, day, hour, minute, second, nanosecond: nanosecond, location: location
      # The nanosecond is not checked: UTC offsets are whole seconds, so no
      # resolution `Time.local` performs can disturb it.
      return unless time.year == year && time.month == month && time.day == day &&
                    time.hour == hour && time.minute == minute && time.second == second

      time
    rescue ArgumentError
      nil
    end

    # Returns the instant at which the UTC offset changes between `earlier` and
    # `later`, or nil when the two carry the same offset.
    #
    # The search runs down to the nanosecond rather than stopping a second
    # short: the result is used both to build materialization hints and to
    # bound stretches of matching time, and a stray fraction of a second in it
    # would carry all the way up through the fields worked out from it.
    def self.transition_between(earlier : Time, later : Time) : Time?
      return if earlier.offset == later.offset

      low, high = earlier, later

      while (high - low) > 1.nanosecond
        middle = low + (high - low) / 2
        break if middle == low || middle == high

        if middle.offset == low.offset
          low = middle
        else
          high = middle
        end
      end

      high
    end

    # Returns how much offset a DST fall-back gives up around `time`, or a zero
    # span when there is no fall-back within a couple of hours either side.
    #
    # Read off the zone rather than assumed, and from both sides, since `time`
    # may be either the first or the second of the two occurrences. Most zones
    # step back an hour; Lord Howe steps back half of one.
    def self.dst_fold_at(time : Time) : Time::Span
      fold = ((time - 2.hours).offset - (time + 2.hours).offset).seconds
      fold > Time::Span.zero ? fold : Time::Span.zero
    rescue ArgumentError
      # Too near the end of the representable calendar to look either way
      Time::Span.zero
    end

    # Returns the earliest answer at or after `floor` that `block` can be
    # brought to give, by re-asking it from the seeds `seeds` names for each
    # answer in turn.
    #
    # A `VirtualTime` fills a rule's unconstrained fields from the hint it is
    # handed, so an answer overshoots whenever the hint carries more detail
    # than the question: a rule naming only a month, asked from the 28th, lands
    # on the 28th of that month rather than on its 1st. Re-asking from the
    # start of the unit the answer fell in brings it back down, and a few
    # rounds of it settle, each seed being coarser than the detail it corrects.
    def self.refine_earliest(best : Time, floor : Time, passes : Int32, seeds : Time -> Array(Time), & : Time -> Time?) : Time
      passes.times do
        improved = false

        seeds.call(best).each do |seed|
          candidate = yield seed
          next unless candidate && floor <= candidate < best

          best = candidate
          improved = true
        end

        break unless improved
      end

      best
    end
  end

  module RangeHelper
    # Returns the last value included in `range`, or `nil` if it contains no values.
    def self.last(range : Range(Int32, Int32)) : Int32?
      # Nothing lies below Int32::MIN, so an exclusive range ending there is
      # empty -- said before the subtraction below can overflow.
      return if range.exclusive? && range.end == Int32::MIN
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

    # Returns whether the stepped range yields `element`.
    #
    # Arithmetic rather than iteration, for the same reason `#intersect?` is:
    # a stepped range over a second's worth of nanoseconds holds hundreds of
    # millions of values, and walking them to answer a single comparison is
    # exactly what the plain ranges beside it are careful never to do.
    def self.includes?(value : Steppable::StepIterator(Int32, Int32, Int32), element : Int32) : Bool
      step = value.step
      return false if step == 0

      first = value.current
      last = value.limit

      if step > 0
        return false if element < first
        return false if value.exclusive ? element >= last : element > last
      else
        return false if element > first
        return false if value.exclusive ? element <= last : element < last
      end

      # In `Int64`: the distance between two `Int32`s can itself overflow `Int32`
      (element.to_i64 - first) % step == 0
    end

    # Returns the smallest value the stepped range yields, or nil when it
    # yields none.
    def self.smallest(value : Steppable::StepIterator(Int32, Int32, Int32)) : Int32?
      return if empty_step? value

      step = value.step
      return value.current if step > 0

      # In `Int64`: the span between the bounds can overflow `Int32`, and the
      # left operand decides a Crystal arithmetic result's type -- so it is
      # the one promoted. The result itself lies between the bounds and fits.
      last = value.exclusive ? value.limit.to_i64 + 1 : value.limit.to_i64
      (value.current + ((value.current.to_i64 - last) // -step) * step).to_i32
    end

    # Returns the smallest value the stepped range yields that is at least
    # `element`, or nil when it yields none.
    def self.first_from(value : Steppable::StepIterator(Int32, Int32, Int32), element : Int32) : Int32?
      return if empty_step? value

      step = value.step
      first = value.current

      if step > 0
        return first if element <= first

        # In `Int64`, since the distances involved can overflow `Int32`. The
        # candidate is a member ≥ `first` by construction, so only the upper
        # limit is left to check before narrowing back down.
        candidate = first.to_i64 + ((element.to_i64 - first + step - 1) // step) * step
        last = value.exclusive ? value.limit.to_i64 - 1 : value.limit.to_i64
        candidate <= last ? candidate.to_i32 : nil
      else
        return if element > first

        # A descending run reaches its own smallest value and stops; asking for
        # anything at or below that is asking for exactly it.
        bottom = smallest value
        return bottom if bottom && element <= bottom

        # In `Int64` for the same reason; the result lies between `element`
        # and `first` and fits.
        span = value.step.to_i64.abs
        (first - ((first.to_i64 - element) // span) * span).to_i32
      end
    end

    # Returns how many values the range or stepped range yields, or nil for
    # a value whose size is not knowable arithmetically.
    #
    # In `Int64`, since a range over `Int32` bounds can hold more values than
    # `Int32` counts.
    def self.count(value) : Int64?
      case value
      when Range(Int32, Int32)
        (last = last(value)) ? last.to_i64 - value.begin + 1 : 0_i64
      when Steppable::StepIterator(Int32, Int32, Int32)
        first = smallest value
        return 0_i64 unless first

        bound = value.step > 0 ? (value.exclusive ? value.limit.to_i64 - 1 : value.limit.to_i64) : value.current.to_i64
        (bound - first) // value.step.abs + 1
      end
    end

    # Returns whether the stepped range yields no value at all.
    #
    # Worked out from the bounds rather than by stepping, which would mean
    # copying the iterator -- it is stateful -- on every comparison.
    def self.empty_step?(value : Steppable::StepIterator(Int32, Int32, Int32)) : Bool
      step = value.step
      return true if step == 0

      if step > 0
        value.exclusive ? value.current >= value.limit : value.current > value.limit
      else
        value.exclusive ? value.current <= value.limit : value.current < value.limit
      end
    end

    # Returns `value` ready to be iterated from its first element.
    #
    # `Steppable::StepIterator`s are stateful and are consumed by iteration,
    # so they must be copied before every traversal; everything else is
    # returned as-is.
    def self.restart(value : Steppable::StepIterator(Int32, Int32, Int32))
      # Rebuilt rather than duplicated: `#dup` carries the consumption state
      # with it, so an iterator someone has read one value from would go on
      # describing a shorter rule than the one it was written as -- and two
      # rules that compare and hash equal would match differently.
      value.current.step to: value.limit, by: value.step, exclusive: value.exclusive
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
        # An empty list would be written as an empty scalar, which YAML reads
        # back as null -- turning "matches nothing" into "matches anything".
        # There is no notation for it, so say so rather than invert the rule.
        if value.empty?
          raise ArgumentError.new "An empty list has no YAML representation; use `false` to mean \"never matches\""
        end
        yaml.scalar value.join ","
      else
        raise "Cannot convert #{value.class} to YAML"
      end
    end

    def self.from_yaml(value : String | IO) : VirtualTime::Virtual
      # Read an IO's contents, not its `#to_s` -- only `IO::Memory` happens to
      # render as its buffer; a pipe or file renders as its inspect text.
      parse_from(value.is_a?(IO) ? value.gets_to_end : value)
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
        # A step may be negative: `20.step(to: 2, by: -2)` is a legal value, and
        # `#to_yaml` writes it out in exactly this form
      when /^(-?\d+)\.\.\.(-?\d+)(?:\/(-?\d+))$/
        ($1.to_i...$2.to_i).step($3.to_i)
      when /^(-?\d+)\.\.\.(-?\d+)$/
        $1.to_i...$2.to_i
      when /^(-?\d+)\.\.(-?\d+)(?:\/(-?\d+))$/
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
      yaml.scalar value.name
    end

    def self.from_yaml(value : String | IO) : Time::Location
      # As in `VirtualConverter`: read an IO's contents, not its `#to_s`
      load(value.is_a?(IO) ? value.gets_to_end : value)
    end

    def self.from_yaml(value : YAML::ParseContext, node : YAML::Nodes::Node) : Time::Location
      unless node.is_a?(YAML::Nodes::Scalar)
        node.raise "Expected scalar, not #{node.class}"
      end
      load node.value
    end

    # Returns the location `name` denotes.
    #
    # A `Time::Location.fixed` -- which is what a timestamp parsed from an
    # offset such as `+02:00` carries -- is named after that offset, and
    # `Time::Location.load` does not accept such a name. Written out and read
    # back through `.load` alone, those locations produce a document this very
    # converter cannot load.
    private def self.load(name : String) : Time::Location
      if offset = name.match(/\A([+-])(\d{2}):(\d{2})(?::(\d{2}))?\z/)
        seconds = offset[2].to_i * 3600 + offset[3].to_i * 60 + (offset[4]?.try(&.to_i) || 0)
        return Time::Location.fixed(offset[1] == "-" ? -seconds : seconds)
      end

      Time::Location.load name
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
    # - `Result::Blocked` if `max_shifts` is exhausted before a candidate is accepted
    # - `Result::OutOfBounds` if `max_shift` or `domain` is exceeded
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
    def self.shift_from_base(base : Time, step : Time::Span, *, domain : Domain? = nil, max_shift : Time::Span? = nil, max_shifts : Int32? = nil, &blocked : Time -> Bool) : Result::Result # ameba:disable Metrics/CyclomaticComplexity
      return Result::InvalidStep.new if step == 0.seconds
      # No shift is permitted at all, which is the `max_shifts` bound being
      # exhausted before the first candidate rather than a bound on distance.
      return Result::Blocked.new if max_shifts && max_shifts <= 0

      current = base
      delta = Time::Span.zero
      shifts = 0

      loop do
        # successor step. Walking far enough runs off the end of the calendar
        # `Time` can represent, which is a bound like any other rather than
        # something for a caller of a Result-returning method to catch. A span
        # near `Time::Span::MAX` overflows the `Int64` arithmetic inside
        # `Time#+` before the range check can speak -- same bound, other voice.
        begin
          current = current + step
        rescue ArgumentError | OverflowError
          return Result::OutOfBounds.new
        end

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
      # the maximum number of step applications. The product (and `abs` itself,
      # for `Time::Span::MIN`) can overflow for enormous steps; a bound larger
      # than every representable span is simply no bound.
      effective_max_shift = max_shift || begin
        step.abs * max_shifts
      rescue OverflowError
        Time::Span::MAX
      end

      current = target
      shifts = 0

      loop do
        # successor behavior is in inverse direction: first base is target - step.
        # Running off the end of the representable calendar means there is no
        # such base left to find -- whether the range check or the `Int64`
        # arithmetic inside `Time#-` is the one to say so.
        begin
          current = current - step
        rescue ArgumentError | OverflowError
          return false
        end

        shifts += 1

        return false if shifts > max_shifts

        # A base farther out than the bound cannot reach the target with a
        # legal delta at all -- the only delta that reaches it *is* that
        # distance -- so it is not worth asking the producer about.
        distance = target - current
        return false if distance.abs > effective_max_shift

        if produced = producer.call(current)
          # `current + produced == target` is exactly `produced == distance`,
          # and comparing spans cannot overflow the way adding an enormous
          # produced span to a `Time` would. Being within
          # `effective_max_shift` follows, since a match equals `distance`.
          return true if produced == distance
        end
      end
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
