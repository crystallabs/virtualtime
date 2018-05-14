require "../src/crystime"

vd = Crystime::VirtualDate["JAN 2018"]
p vd.month == 1

vd = Crystime::VirtualDate["2018 sun"]
p vd.day_of_week == 0

