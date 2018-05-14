require "./spec_helper"

describe Crystime::Span do
  it "can do Span math" do
    a= Crystime::Span.new 10, 10, 10
    b= Crystime::Span.new 12, 12, 12
    a.total_seconds.should eq 36610
    b.total_seconds.should eq 43932
    c= a+ b
    c.total_seconds.should eq 36610+ 43932
    d= b- a
    d.total_seconds.should eq 43932- 36610
  end
end
