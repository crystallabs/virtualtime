require "./spec_helper"

# Collection of tests for interoperability between VirtualTimes and Times.

describe "Crystime::VirtualTime and Times" do

	it "can match Crystal's Time structs" do
		vt= Crystime::VirtualTime.new

		Crystime::Helpers.matches?( vt, [Time.now]).should be_true

		vt.month= 3
		vt.day = (10..20).step(2)

		Crystime::Helpers.matches?( vt, [Time.parse("2018-03-10", "%F")]).should be_true
		Crystime::Helpers.matches?( vt, [Time.parse("2018-03-11", "%F")]).should be_nil
	end
end
