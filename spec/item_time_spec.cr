require "./spec_helper"

# Collection of tests for interoperability between Item and Time.

describe "Crystime::Item and Times" do

  it "can use Crystal's Time structs in place of VTs" do
    i= Crystime::Item.new
    tn= Time.now # Time.parse("2018-04-04", "%F")

    i.on?( tn).should be_true

    i.due<< tn
    i.on?( tn).should be_true

    i.omit<< tn
    i.on?( tn).should be_false

  end
end
