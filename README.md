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

An item can have a start and end date, a list of VirtualDates on which it is considered
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
```

This would print

```
false
false
true
true
true
```
