[![Linux CI](https://github.com/crystallabs/virtualtime/workflows/Linux%20CI/badge.svg)](https://github.com/crystallabs/virtualtime/actions?query=workflow%3A%22Linux+CI%22+event%3Apush+branch%3Amaster)
[![Version](https://img.shields.io/github/tag/crystallabs/virtualtime.svg?maxAge=360)](https://github.com/crystallabs/virtualtime/releases/latest)
[![License](https://img.shields.io/github/license/crystallabs/virtualtime.svg)](https://github.com/crystallabs/virtualtime/blob/master/LICENSE)

# VirtualTime

VirtualTime is a Time-related class for Crystal. It is used for matching and generation of compliant dates and times, primarily for calendar, scheduling, and reminding purposes.

It is a companion project to [virtualdate](https://github.com/crystallabs/virtualdate).

## Installation

Add the following to your application's "shard.yml":

```
dependencies:
  virtualtime:
    github: crystallabs/virtualtime
    version: ~> 1.0
```

And run `shards install` or just `shards`.

## Overview of Functionality

As mentioned, VirtualTime is used for matching and generation of `Time`s.

### 1. Matching Times

One can express date and time constraints in the `VirtualTime` object and then match various `Time`s against it
to determine which ones match.

For example, let's create a VirtualTime that matches the last Saturday and Sunday of every month.
This can be expressed using two constraints:

- Day of month should be between -8 and -1 (the last 7 days of any month)
- Day of week should be 6 or 7 (Saturday and Sunday)

```cr
vt = VirtualTime.new
vt.day = -8..-1
vt.day_of_week = [6,7]

# Check if current time matches
vt.matches?(Time.local) # => result depends on current time
```

### 2. Matching VirtualTimes

In addition to matching `Time`s, it is also possible to match `VirtualTime`s against each other.

Let's say we are interested to know whether the above VT would match any day in the month of March.

We could do this with:

```cr
# Same VT as before:
vt = VirtualTime.new
vt.day = -8..-1
vt.day_of_week = [6,7]

# Check if the specified VT matches any day in month of March
any_in_march = VirtualTime.new month: 3
vt.matches?(any_in_march) # => true
```

Note that `#matches?` is commutative and it could have also been written as `any_in_march.matches?(vt)`.

### 3. Time Generation

In addition to matching, it is also possible to successively generate `Time`s that match the specified
VirtualTime constraints. This is done using the standard iterator approach.

For example, let's take the same `VirtualTime` as above which matches the last weekend days of every month,
and print a list of the next 10 such dates:

```cr
vt = VirtualTime.new
vt.year = 2020..2030
vt.day = -7..-1
vt.day_of_week = [6,7]

vti = vt.step(1.day)

10.times do
  p vti.next
end

# 2024-01-27 11:16:00.0 +01:00 Local
# 2024-01-28 11:16:00.0 +01:00 Local
# 2024-02-24 11:16:00.0 +01:00 Local
# 2024-02-25 11:16:00.0 +01:00 Local
# 2024-03-30 11:16:00.0 +01:00 Local
# 2024-03-31 12:16:00.0 +02:00 Local
# 2024-04-27 12:16:00.0 +02:00 Local
# 2024-04-28 12:16:00.0 +02:00 Local
# 2024-05-25 12:16:00.0 +02:00 Local
# 2024-05-26 12:16:00.0 +02:00 Local
```

## Supported Property Values

Crystal's `struct Time` has all its fields (year, month, day, hour, minute, second, nanosecond) set
to a specific numeric value. Even if some of its fields aren't required in the constructor,
internally they still get initialized to 0, 1, or other suitable value.

As such, `Time` instances always represent specific dates and times ("materialized" dates and times).

On the other hand, `VirtualTime`s do not have to represent any specific points in time (although they can
be defined precisely enough (or converted) so that they do).
They are primarily intended for conveniently matching broader sets of values.

All VirtualTime instances contain the following properties:

1. **Year** (0..9999)
1. **Month** (1..12)
1. **Day** (1..31)
1. **Week number of year** (0..53)
1. **Day of week** (1..7, Monday == 1)
1. **Day of year** (1..366)
1. **Hour** (0..23)
1. **Minute** (0..59)
1. **Second** (0..59)
1. **Millisecond** (0..999)
1. **Nanosecond** (0..999_999_999)

And each of these properties can have a value of the following types:

1. **Nil**, to default to `VirtualTime.default_match? : Bool = true`
1. **Boolean**, to always match (`true`) or fail (`false`)
1. **Int32**, to match a specific value such as 5, 12, 2023, -1, or -5
1. **Array or Set of Int32s**, such as [1,2,10,-1] to match any value in list
1. **Range of Int32..Int32**, such as `10..20` to match any value in range
1. **Range with step**, e.g. `day: (10..20).step(2)`, to match all even days between 10th and 20th
1. **Proc**, to match a value if the return value from calling a proc is `true`

All properties (that are specified, i.e. not nil) must match for the match to succeed.
Properties that *are* nil will match depending on the value of `#default_match?`.

Knowing the structure of `VirtualTime` now, let's create a more elaborate example:

```cr
vt = VirtualTime.new
vt.month = 3                # Month of March
vt.day = [1,-1]             # First and last day of every month
vt.hour = (10..20)          # Hour between 10 and 20, inclusively
vt.minute = (0..59).step(2) # Every other (even) minute in an hour
vt.second = true            # Unconditional match
vt.millisecond = ->( val : Int32) { true } # Unconditional match, since block returns true
vt.location = Time::Location.load("Europe/Amsterdam")

vt.matches?(Time.local) # => result depends on current time
```

## Level of Granularity

VirtualTime performs all internal calculations using maximum precision available from the
`Time` struct (nanoseconds), but since the primary intended usage is for human scheduling,
a decision was made that default displayed granularity is 1 minute, with seconds and
nanoseconds defaulting to 0.

For maximum precision, user simply has to supply intervals and steps manually, e.g.
`1.nanosecond` instead of the default `1.minute`.

As a related, opposite problem, the default interval of 1 minute could be too small. For example,
if VirtualTime was created with only the `hour` value specified, it would match (and also
generate) and event on every minute of that hour.

In that case, a user could require step to be 1 hour or 1 day, so that there would be reasonable
space between the generated `Time`s.

For example:

```cr
vt = VirtualTime.new
vt.year = 2020..2030
vt.day = -8..-1
vt.day_of_week = [6,7]

vti = vt.step(1.minute)
2.times do p vti.next end
# 2024-01-27 11:16:00.0 +01:00 Local
# 2024-01-27 11:17:00.0 +01:00 Local

vti = vt.step(1.day)
2.times do p vti.next end
# 2024-01-27 11:16:00.0 +01:00 Local
# 2024-01-28 11:16:00.0 +01:00 Local
```

## Property Values in Detail

As can be seen above, fields can have some interesting values, such as negative numbers.

Here is a list of all non-obvious values that are supported:

### Negative integer values

Negative integer values count from the end of the range, if the max / wrap-around value is
specified. Typical end values are 7, 12, 30/31, 365/366, 23, 59, and 999, and virtualtime
implicitly knows which one to apply in every case.
For example, a day of `-1` would always match the last day of the month, be that 28th, 29th,
30th, or 31st in a particular case.

If the wrap-around value is not specified, negative values are not converted to positive
ones, and they enter matching as-is. In practice, this means they will not match any `Time`s,
but may match similar `VirtualTime`s.

### Week numbers

Another interesting case is week number, which is calculated as number of Mondays in the year.
The first Monday in a year starts week number 1. But since not every year starts on Monday, up to
the first 3 days of a new year can still technically belong to the last week of the previous year.

That means it is possible for this field to have values between 0 and 53.
Value 53 indicates a week that has started in one year (53rd Monday seen in a year),
but at least one (and up to 3) of its days will surely overflow into the new year.

Similarly, a value 0 matches up to the first 3 days (which inevitably must be Friday, Saturday,
and/or Sunday) of the new year that belong to the week started in the previous year.

Note: if you want to match the first or last 7 days of a year irrespective of weeks, you
should use `day: 1..7` or `day: -7..-1` instead.

### Range values

Crystal allows one to define `Range`s that have `end` value smaller than `begin`.
Such objects will simply not contain any elements.

Because creating such ranges *is* allowed, VirtualTime detects such cases and creates
copies of objects with values converted to positive and in the correct order.

In other words, if you specify a range of say, `day: (10..-7).step(2)`, this will properly
match every other day from 10th to a day 7 days before the end of a month.

### Days in month and year

When matching `VirtualTime`s to other `VirtualTime`s, helper functions `days_in_month` and
`days_in_year` return `0`. As a consequence, matching is performed without converting
negative values to positive ones.

This choice was made because it is only possible to know the number of days in a month
if both `year` and `month` are defined and contain integers.
If they are not both defined, or they contain a value of any other type (e.g. a range
`2023..2030`), it is ambiguous or indeterminable what the exact value should be.

### Unsupported Comparisons

Comparisons between VirtualTime property values which are both a `Proc` are not supported
and will throw `ArgumentError` in runtime.

Comparisons between VirtualTime objects with different `location` values are not supported
and will throw `ArgumentError` in runtime.

## Materialization

"Materialization" is a process of converting all VirtualTime property values to specific
integers.

VirtualTimes often need to be "materialized", for example for display, calculation, comparison,
or further conversion.

An obvious such case is when `to_time()` is invoked on a VT, because a Time object must have
all of its fields set.

Because VirtualTimes can be very broadly defined, often times there are many equal
choices to which VTs can be materialized. For example, if a VT matches anything in the
month of March, which specific value should it be materialized to?

To avoid the problem of too many choices, materialization takes as an argument a time hint,
and the materialized time will be as close as possible to that time, taking VT constraints
in account.

For example:

```crystal
vt= VirtualTime.new

# These fields will be used as-is since they have a value:
vt.year= 2018
vt.day= 15
vt.hour= 0

# While others (which are nil) will have their value inserted from the "hint" object:
hint= Time.local # 2023-12-09 12:56:26.837441132 +01:00 Local

vt.materialize(hint).to_tuple # ==> {2018, 12, 15, nil, nil, nil, 0, 56, 26, nil, 837441132, nil}
```

If not specified, the time hint defaults to current local time.

## Time Zones

`VirtualTime` is timezone-agnostic. Values are compared against `VirtualTime` values directly.

However, `VirtualTime` has property `#location` which, if set and different than the other
object's `#location`, will cause the object to be duplicated and have its time converted to
`VirtualTime`'s location before matching.

```cr
vt = VirtualTime.new
vt.hour = 16..20

t = Time.local 2023, 10, 10, hour: 0, location: Time::Location.load("Europe/Berlin")
vt.matches?(t) # ==> nil, because 00 hours is not between 16 and 20

vt.location = Time::Location.load("America/New_York")
vt.matches?(t) # ==> true, because time instant 0 hours converted to NY time (-6) is 18 hours
```

## Tests

Run `crystal spec` or just `crystal s`.

## API Documentation

Run `crystal docs` or `crystal do` and `firefox ./docs/index.html`.

## Other Projects

List of interesting or similar projects in no particular order:

- https://dianne.skoll.ca/projects/remind/ - a sophisticated calendar and alarm program
