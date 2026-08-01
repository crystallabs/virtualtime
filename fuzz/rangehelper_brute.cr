require "../src/virtualtime"

# Brute-force verify RangeHelper arithmetic against actual StepIterator iteration.

alias RH = VirtualTime::RangeHelper
alias SI = Steppable::StepIterator(Int32, Int32, Int32)

def fresh(first, limit, step, excl) : SI
  first.step(to: limit, by: step, exclusive: excl).as(SI)
end

fails = 0
checks = 0

(-6..6).each do |first|
  (-6..6).each do |limit|
    ((-4..4).to_a - [0]).each do |step|
      [true, false].each do |excl|
        actual = fresh(first, limit, step, excl).to_a

        # empty_step?
        it = fresh(first, limit, step, excl)
        got = RH.empty_step?(it)
        exp = actual.empty?
        checks += 1
        if got != exp
          fails += 1
          puts "empty_step? MISMATCH first=#{first} limit=#{limit} step=#{step} excl=#{excl}: got=#{got} expected=#{exp} (actual values=#{actual})"
        end

        # smallest
        it = fresh(first, limit, step, excl)
        got_s = RH.smallest(it)
        exp_s = actual.min?
        checks += 1
        if got_s != exp_s
          fails += 1
          puts "smallest MISMATCH first=#{first} limit=#{limit} step=#{step} excl=#{excl}: got=#{got_s.inspect} expected=#{exp_s.inspect} (actual=#{actual})"
        end

        (-10..10).each do |e|
          # includes?
          it = fresh(first, limit, step, excl)
          got_i = RH.includes?(it, e)
          exp_i = actual.includes?(e)
          checks += 1
          if got_i != exp_i
            fails += 1
            puts "includes? MISMATCH first=#{first} limit=#{limit} step=#{step} excl=#{excl} e=#{e}: got=#{got_i} expected=#{exp_i} (actual=#{actual})"
          end

          # first_from: smallest yielded value >= e
          it = fresh(first, limit, step, excl)
          got_f = RH.first_from(it, e)
          exp_f = actual.select { |v| v >= e }.min?
          checks += 1
          if got_f != exp_f
            fails += 1
            puts "first_from MISMATCH first=#{first} limit=#{limit} step=#{step} excl=#{excl} e=#{e}: got=#{got_f.inspect} expected=#{exp_f.inspect} (actual=#{actual})"
          end
        end
      end
    end
  end
end

puts "T1 done: #{checks} checks, #{fails} failures"
