require "./spec_helper"

describe Crystime::Span do
  it "can do Span math" do
    a= Crystime::Span.new 10, 10, 10
    b= Crystime::Span.new 12, 12, 12
    a.total_seconds.should eq 36_610
    b.total_seconds.should eq 43_932
    c= a+ b
    c.total_seconds.should eq 36_610+ 43_932
    d= b- a
    d.total_seconds.should eq 43_932- 36_610
  end
end
