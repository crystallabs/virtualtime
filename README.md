Crystime is an advanced time, calendar, scheduling, and reminding library for Crystal.

## VirtualDate

The basis of the low-level functionality is class "VirtualDate". Think of it as of
a normal "Time" struct, but much more powerful.

With regular Time, all fields (year, month, day, hour, minute, second, millisecond) have
a value, and that value is a specific number. As such, Time objects always represent
specific dates ("materialized" dates in Crystime terminology).

With Crystime's VirtualDate, each field (year, month, day, hour, minute,
second, millisecond, day of week, and julian day) can either remain unspecified, or
be a number, or contain a more complex specification (range, range with step, boolean,
or proc).

For example, you could construct a VirtualDate with a month of "March" and a day range
of 10..20 with step 2. This would represent a "virtual date" that matches any Time or
another VirtualDate which falls on, or overlaps, the dates March 10, 12, 14, 16, 
18, or 20.

## Item

The basis of the higher-level, user functionality is class "Item". This is intentionally
called an "item" not to imply any particular type (task, event, recurring appointment,
etc.)

An item can have a start and end VirtualDate, a list of VirtualDates on which it is considered
"on" (i.e. active, due, scheduled), a list of VirtualDates on which it is specifically
"omitted" (i.e. "not on", like on weekends, individual holidays dates, certain times of
day, etc.),
and a rule which specifies what to do if an event falls on an omitted date or time &mdash;
it can be still "on", or ignored, or scheduled some time before, or some time after.

Here's a simple example from the examples/ folder to begin with, with comments:

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
p item.on?( Crystime::VirtualDate["2017-02-15"])== true

# Item is not due on Mar 15, 2017 because that's not a day of
# March 10, 12, 14, 16, 18, or 20:
p item.on?( Crystime::VirtualDate["2017-03-15"])== true

# But item is due on Mar 16, 2017:
p item.on?( Crystime::VirtualDate["2017-03-16"])== true

# Also it is due on Mar 20, 2017:
p item.on?( Crystime::VirtualDate["2017-03-20"])== true

# And it is due on any Mar 20, doesn't need to be in 2017:
any_mar_20 = Crystime::VirtualDate.new
any_mar_20.month = 3
any_mar_20.day = 20
p item.on?( any_mar_20 )== true

# Also, we can check whether this event is due at any point in
# March, and it'll tell us yes:
any_mar = Crystime::VirtualDate.new
any_mar.month = 3
p item.on?( any_mar)== true
```

This would print

```
false
false
true
true
true
true
```

# VirtualDate in Detail

Every date/time object in Crystime (due dates, omit dates, start/stop dates, dates to check etc.)
are based on VirtualDate. That's because VirtualDate does everything Time does (except maybe
providing some convenience functions) so it is simpler and more powerful to use it everywhere.

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
- A number that is native/accepted for a particular field (e.g. 1)
  (Negative values count from the end)
- A range (e.g. 1..6)
- A range with a step (e.g. (1..6).step(2))
- A proc (should return one of {-1, 0, 1} when invoked) (not tested extensively)
```

Please note that weekday and Julian Day Number fields are in relation with the
Y/M/D values. One can't change one without triggering the change in the other.

As long as VirtualDate is materialized (i.e. has specific Y/M/D values), then changing
any of those values will update weekday and jd automatically. Similarly, setting
a Julian Day Number will automatically update Y/M/D and cause the date to become
materialized.

Altogether, this syntax allows for specifying simple but functionally intricate
rules:

```
day=-1                 -- matches last day in month
weekday=6, day=24..31  -- matches last Saturday in month
weekday=1..5, day=-1   -- matches last day of month if it is a workday
```

Please note that these are the individual VirtualDate rules. Complete Items
(described below) can have multiple VirtualDates set as their due and omit
dates so virtually any desired combinations can be expressed.

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
           - Crystime::Span: amount by which it should be shifted

# Reminder capabilities were previously in, but now they are
# waiting for a rewrite.
```

# Additional Info

All of the features are covered by specs, please see spec/* for more ideas
and actual, working examples.

