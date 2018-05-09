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

An item can have an absolute start and end VirtualDate, a list of VirtualDates on which it is considered
"on" (i.e. active, due, scheduled), a list of VirtualDates on which it is specifically
"omitted" (i.e. "not on", like on weekends, individual holidays dates, certain times of
day, etc.),
and a rule which specifies what to do if an event falls on an omitted date or time &mdash;
it can still be "on", or ignored, or scheduled some time before, or some time after.

Here is a simple example from the examples/ folder to begin with, with comments:

```crystal
# Create an item:
item = Crystime::Item.new

# Create a VirtualDate that matches every other
# day from Mar 10 to Mar 20:
due_march = Crystime::VirtualDate.new
due_march.month = 3
due_march.day = (10..20).step 2

# Add this VirtualDate as due date to item:
item.due<< due_march

# Now we can check when the item is due and when not:

# Item is not due on Feb 15, 2017 because that's not in March:
p item.on?( Crystime::VirtualDate["2017-02-15"]) # ==> false

# Item is not due on Mar 15, 2017 because that's not a day of
# March 10, 12, 14, 16, 18, or 20:
p item.on?( Crystime::VirtualDate["2017-03-15"]) # ==> false

# But item is due on Mar 16, 2017:
p item.on?( Crystime::VirtualDate["2017-03-16"]) # ==> true

# Also it is due on Mar 20, 2017:
p item.on?( Crystime::VirtualDate["2017-03-20"]) # ==> true

# And it is due on any Mar 20, doesn't need to be in 2017:
any_mar_20 = Crystime::VirtualDate.new
any_mar_20.month = 3
any_mar_20.day = 20
p item.on?( any_mar_20 ) # ==> true

# Also, we can check whether this event is due at any point in
# March, and it'll tell us yes:
any_mar = Crystime::VirtualDate.new
any_mar.month = 3
p item.on?( any_mar) # ==> true
```

# VirtualDate in Detail

All date/time objects in Crystime (due dates, omit dates, start/stop dates, dates to check etc.)
are based on VirtualDate. That is because VirtualDate does everything Time does, except maybe
providing some convenience functions, so it is simpler and more powerful to use it everywhere.

(If you are missing any particular convenience/compatibility functions from Time, please report
them or submit a PR.)

A VirtualDate has the following fields that can be set after object creation:

```
year        - Year value
month       - Month value (1-12)
day         - Day value (1-31)

weekday     - Day of week (Sunday = 0, Saturday = 6)
jd          - Julian Day Number

hour        - Hour value (0-23)
minute      - Minute value (0-59)
second      - Second value (0-59)
millisecond - Millisecond value (0-999)
```

Each of the above listed fields can have the following values:

```
- Nil / undefined (matches everything it is compared with)
- A number that is native/accepted for a particular field, e.g. 1 or -2
  (negative values count from the end)
- A list of numbers native/accepted for a particular field, e.g. [1, 2] or [1, -2]
  (negative values count from the end)
- A range, e.g. 1..6
- A range with a step, e.g. (1..6).step(2)
- A proc (must accept Int32 as arg, and return Bool) (not tested extensively)
```

Please note that the weekday and [Julian Day Number](https://en.wikipedia.org/wiki/Julian_day) fields are in relation with the
Y/M/D values. One can't change one without triggering an automatic change in the other. Specifically:

As long as VirtualDate is materialized (i.e. has specific Y/M/D values), then changing
any of those values will update `weekday` and `jd` automatically. Similarly, setting
Julian Day Number will automatically update Y/M/D and cause the date to become
materialized.

Altogether, the described syntax allows for specifying simple but functionally intricate
rules, of which just some of them are:

```
day=-1                 -- matches last day in month
weekday=6, day=24..31  -- matches last Saturday in month
weekday=1..5, day=-1   -- matches last day of month if it is a workday
```

Please note that these are individual VirtualDate rules. Complete Items
(described below) can have multiple VirtualDates set as their due, omit,
and check dates, so really arbitrary rules can be expressed. (In the case of
multiple VDs for a field, the matches are logically OR-ed, i.e. one match is
enough for the field to match.)

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
vd.millisecond = ->() { return 1 }
```

Another is creating a VirtualDate from a string, using notation `vd = VirtualDate["... string ..."]`.
This parser should eventually support everything supported by Ruby's `Time.parse`, `Date.parse`,
`DateTime.parse`, etc., but for now it supports the following strings:

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
p vd.month == 1

vd = VirtualDate["2018 sun"]
p vd.weekday == 0
```

## VirtualDate Materialization

VirtualDates sometimes need to be materialized for
the purpose of display, calculation, comparison, or conversion. An obvious such case
is when `to_time()` is invoked on a VD, because a Time object must have all of its
fields set.

For that purpose, each VirtualDate keeps track of which of its 7 fields (YMD, hms, and
millisecond) are set, and which of them are materializable. If any of the individual
fields are not materializable, then the VD is not either, and an Exception is thrown
if materialization is attempted.

Currently, unset values and specific integers are materializable, while fields containing
any other specification are not. This is one of the areas where maybe some improvements
could be made to support more of all possible cases without throwing an Exception.
Also, materialization rules could be added so that a person could choose what the
default values are. For example, to materialize unset hours and minutes to 12:00
instead of to 00:00. Both of these tasks are mentioned in the TODO at the bottom
of the README.

For convenience, the VD's ability to materialize using its current values can be
retrieved by using a getter named `ts`:

```crystal
vd = Crystime::VirtualDate.new

vd.year = nil
vd.month = 3
vd.day = [1,2]
vd.hour = (10..20)
vd.minute = (10..20).step(2)
vd.second = true
vd.millisecond = ->( val : Int32) { return true }

vd.ts # ==> [nil, true, false, false, false, false, false]
```

(Fields containing nil or true are materializable; fields containing false are not.)

# Item in Detail

As mentioned, Item is the toplevel object representing a task/event/etc.

It does not contain task/event-specific properties, it only concerns itself with
the scheduling aspect and has the following fields:

```
start      - Start VirtualDate (item is never "on" before this date)
stop       - End VirtualDate (item is never "on" after this date)

due        - List of due/on VirtualDates
omit       - List of omit/not-on VirtualDates

shift      - List of VirtualDates which new proposed item time (produced by
             shifting the date from an omit date in an attempt to schedule it)
             must match for the item to be considered "on"

omit_shift - What to do if item falls on an omitted date/time:
           - nil: ignore it, do not schedule
           - false: ignore it, treat as not-reschedulable
           - true: treat it as due, regardless of falling on omitted date
           - Crystime::Span: amount by which it should be shifted (can be + or -)

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
not_due_weekend.weekday = [0,6]
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

1. Add fully working serialization to/from JSON and YAML
1. Add reminder functions. Previously remind features were implemented using their
own code/approach. But maybe reminders should be just regular Items whose exact
due date/time is certain offset from the original Item's date/time.
1. Add more compatibility for using Time in place of VirtualDate
1. Add more cases in which a VirtualDate is materializable (currently it is not if any of its values are anything else other than unset or a number)
1. Extend the configuration options for specifying how VDs will be materialized, when materialization is requested or implicitly done
1. Add more features suitable to be used in a reimplementation of cron using this module
1. Add a rbtree or something, sorting the items in order of most recent to most distant due date
1. Possibly add some support for triggering actions on exact due dates of items/reminders
1. Implement a complete task tracking program using Crystime
1. Write support for exporting items into other calendar apps

