require "../src/virtualtime"

alias RH = VirtualTime::RangeHelper

fails = 0
checks = 0

(-6..6).each do |b1|
  (-6..6).each do |e1|
    [true, false].each do |x1|
      r1 = Range.new(b1, e1, x1)
      # last
      got = RH.last(r1)
      exp = r1.to_a.last?
      checks += 1
      if got != exp
        fails += 1
        puts "last MISMATCH #{r1}: got=#{got.inspect} expected=#{exp.inspect}"
      end

      (-6..6).each do |b2|
        (-6..6).each do |e2|
          [true, false].each do |x2|
            r2 = Range.new(b2, e2, x2)
            got_i = RH.intersect?(r1, r2)
            exp_i = !(r1.to_a & r2.to_a).empty?
            checks += 1
            if got_i != exp_i
              fails += 1
              puts "intersect? MISMATCH #{r1} vs #{r2}: got=#{got_i} expected=#{exp_i}"
            end
          end
        end
      end
    end
  end
end

puts "T2 done: #{checks} checks, #{fails} failures"
