require "../src/crystime"

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
# Add this VirtualDate as due date to item:
item.omit<< not_due_weekend

item.omit_shift = nil

# Now let's check when it is due and when not:
(1..31).each do |d|
	p "2017-03-#{d} = #{item.on?( Crystime::VirtualDate["2017-03-#{d}"])== true}"
end
