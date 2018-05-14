Crystime is an advanced time, calendar, scheduling, and reminding library for Crystal.

## VirtualDate

First, the basis of the low-level functionality is class "VirtualDate". Think of it as of
a normal "Time" struct, but much more flexible.

With regular Time, all fields (year, month, day, hour, minute, second, millisecond) must
have a value, and that value must be a specific number. Even if some of Time's fields don't
require you to set a value (such as hour or minute values), they still default to 0
internally. As such, Time objects always represent specific dates ("materialized"
dates in Crystime terminology).

With Crystime's VirtualDate, each field (year, month, day, hour, minute,
second, millisecond, day of week, and [julian day](https://en.wikipedia.org/wiki/Julian_day))
can either remain unspecified, or be a number, or contain a more complex specification
(list, range, range with step, boolean, or proc).

For example, you could construct a VirtualDate with a month of "March" and a day range
of 10..20 with step 2. This would represent a "virtual date" that matches any Time or
another VirtualDate which falls on, or overlaps, the dates of March 10, 12, 14, 16, 18, or 20.

## Item

Second, the basis of the high-level user functionality is class "Item". This is intentionally
called an "item" not to imply any particular type or purpose (e.g. a task, event,
recurring appointment, reminder, etc.)

An item has an absolute start and end VirtualDate, a list of VirtualDates on which it is considered
"on" (i.e. active, due, scheduled), a list of VirtualDates on which it is specifically
"omitted" (i.e. "not on", like on weekends, individual holidays dates, certain times of
day, etc.),
and a rule which specifies what to do if an event falls on an omitted date or time &mdash;
it can still be "on", or ignored, or re-scheduled to some time before, or some time after.

If the item's list of due dates is empty, it is considered as always "on".
If the item's list of omit dates is empty, it is considered as never omitted.
If there are multiple VDs set for a field, the matches are logically OR-ed, i.e. one match is enough for the field to match.

Here is a simple example from the examples/ folder to begin with, with comments:

```crystal
# Create an item:
item = Crystime::Item.new

# Create a VirtualDate that matches every other day from Mar 10 to Mar 20:
due_march = Crystime::VirtualDate.new
due_march.month = 3
due_march.day = (10..20).step 2

# Add this VirtualDate as due date to item:
item.due<< due_march

# Create a VirtualDate that matches Mar 20 specifically. We will use this to actually omit
# the event on that day:
omit_march_20 = Crystime::VirtualDate.new
omit_march_20.month = 3
omit_march_20.day = 20

# Add this VirtualDate as omit date to item:
item.omit<< omit_march_20

# If event falls on an omitted date, try rescheduling it for 2 days later:
item.omit_shift = Crystime::Span.new(86400 * 2)


# Now we can check when the item is due and when it is not:

# Item is not due on Feb 15, 2017 because that's not in March:
p item.on?( Crystime::VirtualDate["2017-02-15"]) # ==> false

# Item is not due on Mar 15, 2017 because that's not a day of
# March 10, 12, 14, 16, 18, or 20:
p item.on?( Crystime::VirtualDate["2017-03-15"]) # ==> false

# Item is due on Mar 16, 2017:
p item.on?( Crystime::VirtualDate["2017-03-16"]) # ==> true

# Item is due on Mar 18, 2017:
p item.on?( Crystime::VirtualDate["2017-03-18"]) # ==> true

# And it is due on any Mar 18, doesn't need to be in 2017:
any_mar_18 = Crystime::VirtualDate.new
any_mar_18.month = 3
any_mar_18.day = 18
p item.on?( any_mar_18 ) # ==> true

# We can check whether this event is due at any point in March:
any_mar = Crystime::VirtualDate.new
any_mar.month = 3
p item.on?( any_mar) # ==> true

# But item is not due on Mar 20, 2017, because that date is omitted, and the system will give us
# a span of time (offset) when it can be scheduled. Based on our reschedule settings above, this
# will be a span for 2 days later.
p item.on?( Crystime::VirtualDate["2017-03-20"]) # ==> #<Crystime::Span @span=2.00:00:00>

# Asking whether the item is due on the rescheduled date (Mar 22) will tell us no, because currently
# rescheduled dates are not counted as due/on dates:
p item.on?( Crystime::VirtualDate["2017-03-22"]) # ==> nil
```

# VirtualDate in Detail

All date/time objects in Crystime (due dates, omit dates, start/stop dates, dates to check etc.)
are based on VirtualDate. That is because VirtualDate does everything Time does (except maybe
providing some convenience functions), so it is simpler and more powerful to use it everywhere.

(If you are missing any particular convenience/compatibility functions from Time, please report
them or submit a PR.)

A VirtualDate has the following fields that can be set after object creation:

```
year        - Year value
month       - Month value (1-12)
day         - Day value (1-31)

day_of_week - Day of week (Sunday = 0, Saturday = 6)
jd          - Julian Day Number

hour        - Hour value (0-23)
minute      - Minute value (0-59)
second      - Second value (0-59)
millisecond - Millisecond value (0-999)
```

Each of the above listed fields can have the following values:

1. Nil / undefined (matches everything it is compared with)
1. A number that is native/accepted for a particular field, e.g. 1 or -2 (negative values count from the end)
1. A list of numbers native/accepted for a particular field, e.g. [1, 2] or [1, -2] (negative values count from the end)
1. A range, e.g. 1..6
1. A range with a step, e.g. (1..6).step(2)
1. True (inserts default values in place of 'true')
1. A proc (accepts Int32 as arg, and returns Bool) (not tested extensively)

## Weekday (Day of Week) and Julian Day Number

The day of week and [Julian Day Number](https://en.wikipedia.org/wiki/Julian_day) fields are in relation with the
Y/m/d values. One can't change one without triggering an automatic change in the other. Specifically:

As long as VirtualDate is materialized (i.e. has specific Y/m/d values), then changing
any of those values will update `day_of_week` and `jd` automatically. Similarly, setting
Julian Day Number will automatically update Y/m/d (and implicitly also day of week) and cause the
date to become materialized.

Please note that in the current behavior, setting `day_of_week` will not affect Y/m/d or jd.
In essence if Y/m/d is set and day of week is later changed
from its existing/auto-computed value, it will probably no longer match any date,
because the date and day of week will be out of sync. This behavior
may be useful in rare circumstances (most probably generated by some
automated script) where you want to match a fixed date, but only if
that date also happens to fall on a specified day of week.

Please also note that in the current behavior, de-materializing a VD
resets both `day_of_week` and `jd` to nil.

The current behavior was choosen based on the assumption that it would
be the most intuitive / most useful behavior. It could be changed if
some other behavior is deemed more appropriate.

Altogether, the described syntax allows for specifying simple but functionally intricate
rules, of which just some of them are:

```
day=-1                     -- matches last day in month
day_of_week=6, day=24..31  -- matches last Saturday in month
day_of_week=1..5, day=-1   -- matches last day of month if it is a workday
```

Please note that these are individual VirtualDate rules. Complete Items
(described below) can have multiple VirtualDates set as their due, omit,
and check dates, so really arbitrary rules can be expressed. 

## VirtualDate from String

There are two ways to create a VirtualDate and both have been implicitly shown
in use above.

One is by invoking e.g. `vd = VirtualDate.new` and then setting the individual
fields on `vd`.

For example:

```crystal
vd = Crystime::VirtualDate.new

vd.year = nil # Remains unspecified, matches everything it is compared with
vd.month = 3
vd.day = [1,2]
vd.hour = (10..20)
vd.minute = (10..20).step(2)
vd.second = true
vd.millisecond = ->( val : Int32) { true }
```

Another is creating a VirtualDate from a string, using notation `vd = VirtualDate["... string ..."]`.
This parser should eventually support everything supported by Ruby's `Time.parse`, `Date.parse`,
`DateTime.parse`, etc., but for now it supports the following strings and their combinations:

```
# Year-Month-Day
yyyy-mm?-dd?
yyyy.mm?.dd?
yyyy/mm?/dd?

# Hour-Minute-Second-Millisecond
hh?:mm?:ss?
hh?:mm?:ss?:mss?
hh?:mm?:ss?.mss?

# Year
yyyy

# Month abbreviations
JAN, Feb, ...

# Day names
MON, Tue, ...

```

For example:

```
vd = VirtualDate["JAN 2018"]
p vd.month == 1 # ==> true

vd = VirtualDate["2018 sun"]
p vd.day_of_week == 0 # ==> true

vd = VirtualDate["2018 wed 12:00:00"]
p vd.day_of_week == 3 # ==> true
```

## VirtualDate Materialization

VirtualDates sometimes need to be fully materialized for
the purpose of display, calculation, comparison, or conversion. An obvious such case
is when `to_time()` is invoked on a VD, because a Time object must have all of its
fields set.

For that purpose, each VirtualDate keeps track of which of its 7 fields (Y, m, d, H, M, S, and
millisecond) are set, and which of them are materializable. If any of the individual
fields are not materializable, then the VD is not either, and an Exception is thrown
if materialization is attempted.

Currently, unset values and specific integers are materializable, while fields containing
any other specification are not. This will be greatly improved in the future so that with
the user-supplied materialization hints, all types can be materialized.

For convenience, the VD's ability to materialize each of its individual fields using their
current values can be checked through a getter named `ts`:

```crystal
vd = Crystime::VirtualDate.new

vd.year = nil
vd.month = 3
vd.day = [1,2]
vd.hour = (10..20)
vd.minute = (10..20).step(2)
vd.second = true
vd.millisecond = ->( val : Int32) { true }

# Fields containing nil or true are materializable; fields containing false are not:
vd.ts # ==> [nil, true, false, false, false, false, false]
```

# Item in Detail

As mentioned, Item is the toplevel object representing a task/event/etc.

It does not contain any task/event-specific properties, it only concerns itself with
the scheduling aspect and has the following fields:

```
start      - Start VirtualDate (item is never "on" before this date)
stop       - End VirtualDate (item is never "on" after this date)

due        - List of due/on VirtualDates
omit       - List of omit/not-on VirtualDates

omit_shift - What to do if item falls on an omitted date/time:
           - nil: treat it as not being "on"
           - false: treat it as being "on", but falling on an omitted
             and non-reschedulable date, so effectively it is not "on"
           - true: treat it as "on", regardless of falling on omitted date
           - Crystime::Span: attempt shifting (rescheduling) by specified span on
             each attempt. The span to shift can be negative or positive for
             shifting to an earlier or later date.

shift      - List of VirtualDates which the new proposed item time (produced by
             shifting the date by omit_shift span in an attempt to reschedule it)
             must match for the item to be considered "on"

# (Reminder capabilities were previously in, but now they are
# waiting for a rewrite and essentially aren't available.)
```

Here's an example of an item that's due every other day in March, but if it falls
on a weekend it is ignored. (This is also one from the examples/ folder.)

```crystal
# Create an item:
item = Crystime::Item.new

# Create a VirtualDate that matches every other day in March:
due_march = Crystime::VirtualDate.new
due_march.month = 3
due_march.day = (2..31).step 2
# Add this VirtualDate as due date to item:
item.due<< due_march

# But on weekends it should not be scheduled:
not_due_weekend = Crystime::VirtualDate.new
not_due_weekend.day_of_week = [0,6]
# Add this VirtualDate as omit date to item:
item.omit<< not_due_weekend

item.omit_shift = nil

# Now let's check when it is due and when not:
(1..31).each do |d|
  p "2017-03-#{d} = #{item.on?( Crystime::VirtualDate["2017-03-#{d}"])}"
end
```

# Additional Info

All of the features are covered by specs, please see spec/* for more ideas
and actual, working examples. To run specs, run the usual command:

```
crystal spec
```

# TODO

1. Add fully working serialization to/from JSON and YAML. Currently YAML serialization works fine, but serializes the object field by field (i.e. year, month, day, etc.) instead of serializing the whole content into an efficient string like "Y/m/d". This makes it inconvenient to serialize Items, as their lists of potentially many serialized VDs would be unwieldy to edit or look into by hand
1. Add reminder functions. Previously remind features were implemented using their own code/approach. But maybe reminders should be just regular Items whose exact due date/time is certain offset from the original Item's date/time.
1. Currently, there is good code for inserting default values is field's value is "true", but there is no ways for users to fill in those defaults
1. Add more cases in which a VirtualDate is materializable (currently it is not if any of its values are anything else other than unset or a number). This should work with the help of user-supplied VD as argument, which will provide hints how to materialize objects in case of ambiguities or multiple choices.
1. Extend the configuration options for specifying how VDs will be materialized, when materialization is requested or implicitly done
1. Add more features suitable to be used in a reimplementation of cron using this module
1. Add a rbtree or something, sorting the items in order of most recent to most distant due date
1. Possibly add some support for triggering actions on exact due dates of items/reminders
1. Implement a complete task tracking program using Crystime
1. Write support for exporting items into other calendar apps

