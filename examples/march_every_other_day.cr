require "../src/crystime"

# Create an item:
item = Crystime::Item.new

# Create a VirtualTime that matches every other day in March:
due_march = Crystime::VirtualTime.new
due_march.month = 3
due_march.day = (2..31).step 2
# Add this VirtualTime as due date to item:
item.due<< due_march

# But on weekends it should not be scheduled:
not_due_weekend = Crystime::VirtualTime.new
not_due_weekend.day_of_week = [0,6]
# Add this VirtualTime as omit date to item:
item.omit<< not_due_weekend

item.omit_shift = nil

# Now let's check when it is due and when not:
(1..31).each do |d|
	p "2017-03-#{d} = #{item.on?( Crystime::VirtualTime["2017-03-#{d}"])}"
end
