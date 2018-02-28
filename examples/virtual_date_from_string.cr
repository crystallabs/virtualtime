require "../src/crystime"

vd = Crystime::VirtualDate["JAN 2018"]
p vd.month == 1

vd = Crystime::VirtualDate["2018 SUN"]
p vd.weekday == 0

