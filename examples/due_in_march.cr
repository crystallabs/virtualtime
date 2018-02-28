require "../src/crystime"

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
p item.on?( Crystime::VirtualDate["2017-02-15"])

# Item is not due on Mar 15, 2017 because that's not a day of
# March 10, 12, 14, 16, 18, or 20:
p item.on?( Crystime::VirtualDate["2017-03-15"])

# But item is due on Mar 16, 2017:
p item.on?( Crystime::VirtualDate["2017-03-16"])

# Also it is due on Mar 20, 2017:
p item.on?( Crystime::VirtualDate["2017-03-20"])

# And it is due on any Mar 20, doesn't need to be in 2017:
any_mar_20 = Crystime::VirtualDate.new
any_mar_20.month = 3
any_mar_20.day = 20
p item.on?( any_mar_20 )

# Also, we can check whether this event is due at any point in
# March, and it'll tell us yes:
any_mar = Crystime::VirtualDate.new
any_mar.month = 3
p item.on?( any_mar)

