[![Linux CI](https://github.com/crystallabs/virtualtime/workflows/Linux%20CI/badge.svg)](https://github.com/crystallabs/virtualtime/actions?query=workflow%3A%22Linux+CI%22+event%3Apush+branch%3Amaster)
[![Version](https://img.shields.io/github/tag/crystallabs/virtualtime.svg?maxAge=360)](https://github.com/crystallabs/virtualtime/releases/latest)
[![License](https://img.shields.io/github/license/crystallabs/virtualtime.svg)](https://github.com/crystallabs/virtualtime/blob/master/LICENSE)

# VirtualTime

VirtualTime is a time matching class for Crystal.
It is a companion project to [virtualdate](https://github.com/crystallabs/virtualdate).

It is used for complex and flexible matching of dates and times, primarily for calendar, scheduling, and reminding purposes.

For example:

```cr
vt = VirtualTime.new
vt.year = 2020..2030
vt.day = -8..-1
vt.day_of_week = [6,7]
vt.hour = 12..16
vt.minute = ->( val : Int32) { true }

time = Time.local

vt.matches? time
```

That `VirtualTime` instance will match any `Time` that is:

- Between years 2020 and 2030, inclusively
- In the last 7 days of each/any month (day = -8..-1; negative values count from the end)
- Falling on Saturday or Sunday (day_of_week = 6 or 7)
- Between hours noon and 4PM (hour = 12..16)
- And any minute (since example block always returns true)

As a more advanced feature, it is also possible to match `VirtualTime`s with other
`VirtualTime`s. That is documented further below.

## Installation

Add the following to your application's "shard.yml":

```
dependencies:
  virtualtime:
    github: crystallabs/virtualtime
    version: ~> 1.0
```

And run `shards install` or just `shards`.

## Introduction

Think of class `VirtualTime` as of a very flexible time specification against which
Crystal's `Time` instances and other `VirtualTime`s can be matched.

Crystal's `struct Time` has all its fields (year, month, day, hour, minute, second, nanosecond) set
to a specific numeric value. Even if some of its fields aren't required in the constructor,
internally they still get initialized to 0, 1, or other suitable value.

As such, `Time` instances always represent specific dates and times ("materialized" dates and times).

On the other hand, `VirtualTime`s do not have to represent any specific points in time (although they can
be set or converted so that they do); they are primarily intended for conveniently matching broader sets of
values. VirtualTime instances contain the following properties:

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
1. **Array of Int32s**, such as [1,2,10,-1] to match any value in list
1. **Range of Int32..Int32**, such as `10..20` to match any value in range
1. **Range with step**, e.g. `day: (10..20).step(2)`, to match all even days between 10th and 20th
1. **Proc**, to match a value if the return value from calling a proc is `true`

All properties (that are specified, i.e. not nil) must match for the match to succeed.

## Matching `Time`s

Once `VirtualTime` is created, it can be used for matching `Time` objects.

Here is again the example from the introduction section, showing use of different value types:

```cr
vt = VirtualTime.new
vt.year = 2020..2030
vt.day = -8..-1
vt.day_of_week = [6,7]
vt.hour = 12..16
vt.minute = ->( val : Int32) { true }

time = Time.local

vt.matches? time
```

As mentioned, this example will match if the time matched is:

- Between years 2020 and 2030, inclusively
- In the last 7 days of each/any month (day = -8..-1; negative values count from the end)
- Falling on Saturday or Sunday (day_of_week = 6 or 7)
- Between hours noon and 4PM (hour = 12..16)
- And any minute (since example block always returns true)

The overall syntax allows for specifying simple but flexible rules, such as:

```txt
day=-1                     -- matches last day of month (28th, 29th, 30th, or 31st of particular month)
day_of_week=6, day=24..31  -- matches last Saturday in month
day_of_week=1..5, day=-1   -- matches last day of month if it is a workday
```

Another example:

```cr
vt = VirtualTime.new

vt.month = 3       # Month of March
vt.day = [1,-1]    # First and last day of every month
vt.hour = (10..20)
vt.minute = (0..59).step(2) # Every other (even) minute in an hour
vt.second = true   # Unconditional match
vt.millisecond = ->( val : Int32) { true } # Will match any value as block returns true
vt.location = Time::Location.load("Europe/Amsterdam")

time = Time.local

vt.matches?(time) # ==> Depends on current time
```

## Matching `VirtualTime`s

In addition to matching `Time` structs, `VirtualTime`s can match other `VirtualTime`s.

For example, if you had a `VirtualTime` that matches every March 15 and you wanted to check
whether this was falling on any day in the first 6 months of the year, you could do:

```cr
vt = VirtualTime.new month: 3, day: 15

vt2 = VirtualTime.new month: 1..6

vt.matches?(vt2) # ==> true
```

It doesn't matter whether you are comparing `vt` to `vt2` or vice-versa, the
operation is commutative.

The only note is that comparisons between field values which are both a `Proc`
are not supported and will throw `ArgumentError` in runtime.

## Field Values in Detail

As can be seen above, fields can have some interesting values, such as negative numbers.

Here is a list of all non-obvious values that are supported:

### Negative integer values

Negative integer values count from the end of the range, if the max / wrap-around value is
specified. Typical end values are 7, 12, 30/31, 365/366, 23, 59, and 999, and virtualtime
implicitly knows which one to apply in every case.
For example, a day of `-1` would always match the last day of the month, be that 28th, 29th,
30th, or 31st in a particular case.

If the wrap-around value is not specified, negative values are not converted to positive
ones, and they enter matching as-is.

### Week numbers

Another interesting case is week number, which is calculated as number of Mondays in the year.
The first Monday in a year starts week number 1. But since not every year starts on Monday, up to
the first 3 days of a new year can still technically belong to the last week of the previous year.

That means it is possible for this field to have values between 0 and 53.
Value 53 indicates a week that has started in one year (53rd Monday seen in a year),
but at least one (and up to 3) of its days will overflow into the new year.

Similarly, a value 0 matches up to the first 3 days (which inevitably must be Friday, Saturday,
and/or Sunday) of the new year that belong to the week started in the previous year.

That allows for a very flexible matching. If you want to match the first or last 7 days of
a year irrespective of weeks, then you should use `day: 1..7` or `day: -7..-1`.

### Range values

Crystal allows one to define `Range`s that have `end` value smaller than `begin`.
Such objects will simply not contain any elements.

Because creating such ranges *is* allowed, VirtualTime detects such cases and creates
copies of objects with values converted to positive and in the correct order.

In other words, if you specify a range of say, `day: (10..-7).step(2)`, this will properly
match every other day from 10th to a day 7 days before the end of the month.

### Days in month and year

When matching `VirtualTime`s to other `VirtualTime`s, helper functions `days_in_month` and
`days_in_year` return `nil`. As a consequence, matching is performed without converting
negative values to positive ones.

This choice was made because it is only possible to know the exact values if/when `year`
and `month` happen to be defined and contain integers.
If they are not both defined, or they contain a value of any other type (e.g. a range
`2023..2030`), it is ambiguous or indeterminable what the exact value should be.

## Materialization

VirtualTimes sometimes need to be "materialized" for
the purpose of display, calculation, comparison, or conversion. An obvious such case
which happens implicitly is when `to_time()` is invoked on a VT, because a Time object
must have all of its fields set.

Because VirtualTimes can be very broadly defined, often times there are many equal
choices to which VTs can be materialized. To avoid the problem of too many choices,
materialization takes as argument a time hint,
and the materialized time will be as close as possible to that time.

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

When comparing `VirtualTime`s to `VirtualTime`s, comparisons between objects with different
`location` values are not supported and will throw `ArgumentError` in runtime.

## Considerations

Alias `Virtual` is defined as:

```cr
alias Virtual = Nil | Bool | Int32 |
  Array(Int32) | Range(Int32, Int32) | Steppable::StepIterator(Int32, Int32, Int32) |
  VirtualProc
```

`Array`, `Range`, and `Steppable::StepIterator` are mentioned explicitly instead of just
being replaced with `Enumerable(Int32)` due to a bug in Crystal
(https://github.com/crystal-lang/crystal/issues/14047).

Another, related consideration is related to matching fields that contain these enumerable
types.

Some enumerables change internal state when they are used, so in the matching function accepting
`Enumerable` data types they are `#dup`-ed before use, to make sure the original objects
remain intact.

An alternative approach, to avoid duplicating objects in every case, would be to define more
specific function overloads for matching `Array`s, `Range`s, and `StepIterator`s, and only have
the `Enumerable` function overload as a fallback, unless a more specific match is found.

Currently the first option for doing all matching via `Enumerable`s is used because it
results is a smaller amount of active code to maintain. But the code for other types exists;
it is just disabled.

Please open an issue on the project to discuss if you would advise differently.

## Tests

Run `crystal spec` or just `crystal s`.

## API Documentation

Run `crystal docs` or `crystal do` and `firefox ./docs/index.html`.

## Other Projects

List of interesting or similar projects in no particular order:

- https://dianne.skoll.ca/projects/remind/ - a sophisticated calendar and alarm program
