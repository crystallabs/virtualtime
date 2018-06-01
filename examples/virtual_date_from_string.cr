require "../src/crystime"

vd = Crystime::VirtualTime["JAN 2018"]
p vd.month == 1

vd = Crystime::VirtualTime["2018 sun"]
p vd.day_of_week == 0
