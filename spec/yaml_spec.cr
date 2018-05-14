require "./spec_helper"
#
#it "can #to_yaml and #from_yaml" do
#  date= Crystime::VirtualTime.new
#  date.year= 2017
#  date.month= 4..6
#  date.day= true
#  date.hour= 2..8/3
#
#  y= date.to_yaml
#  date2= Crystime::VirtualTime.from_yaml y
#  y.should eq date2.to_yaml
#
#  date.hour= 2...10/3
#
#  y= date.to_yaml
#  date2= Crystime::VirtualTime.from_yaml y
#  y.should eq date2.to_yaml
#end
