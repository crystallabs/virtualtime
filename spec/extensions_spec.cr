require "./spec_helper"

describe "Crystime Extensions" do

  it "can expand arrays" do
    [1, 2, [:a, :b], 8..10, [:e, :f]].expand==
      [[1, 2, :a, 8, :e],
       [1, 2, :a, 8, :f],
       [1, 2, :a, 9, :e],
       [1, 2, :a, 9, :f],
       [1, 2, :a, 10, :e],
       [1, 2, :a, 10, :f],
       [1, 2, :b, 8, :e],
       [1, 2, :b, 8, :f],
       [1, 2, :b, 9, :e],
       [1, 2, :b, 9, :f],
       [1, 2, :b, 10, :e],
       [1, 2, :b, 10, :f]]
  end
end
