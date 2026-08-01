require "../src/virtualtime"

alias RH = VirtualTime::RangeHelper
alias SI = Steppable::StepIterator(Int32, Int32, Int32)

# Randomized check with nanosecond-scale magnitudes, verified against
# direct index arithmetic (iterating a billion values is infeasible; use
# small counts with large offsets instead: large first/limit but few steps).
rng = Random.new(42)
fails = 0
checks = 0

5000.times do
  first = rng.rand(-500_000_000..500_000_000)
  nsteps = rng.rand(0..50)
  step = rng.rand(1..100_000_000) * (rng.next_bool ? 1 : -1)
  excl = rng.next_bool
  # construct a limit that lands somewhere near first + nsteps*step
  limit64 = first.to_i64 + nsteps.to_i64 * step + rng.rand(-3..3)
  next if limit64 > 900_000_000 || limit64 < -900_000_000
  limit = limit64.to_i32

  actual = first.step(to: limit, by: step, exclusive: excl).to_a

  it = first.step(to: limit, by: step, exclusive: excl).as(SI)
  checks += 1
  if RH.empty_step?(it) != actual.empty?
    fails += 1
    puts "empty_step? MISMATCH #{first} #{limit} #{step} #{excl}"
  end

  it = first.step(to: limit, by: step, exclusive: excl).as(SI)
  checks += 1
  if RH.smallest(it) != actual.min?
    fails += 1
    puts "smallest MISMATCH #{first} #{limit} #{step} #{excl}: got #{RH.smallest(first.step(to: limit, by: step, exclusive: excl).as(SI)).inspect} exp #{actual.min?.inspect}"
  end

  # elements: probe near boundaries and members +- 1
  probes = [] of Int32
  probes << first << first - 1 << first + 1 << limit << limit - 1 << limit + 1
  actual.first(3).each { |v| probes << v << v - 1 << v + 1 }
  actual.last(3).each { |v| probes << v << v - 1 << v + 1 }
  probes << rng.rand(-500_000_000..500_000_000)

  probes.each do |e|
    it = first.step(to: limit, by: step, exclusive: excl).as(SI)
    got = RH.includes?(it, e)
    exp = actual.includes?(e)
    checks += 1
    if got != exp
      fails += 1
      puts "includes? MISMATCH #{first} #{limit} #{step} #{excl} e=#{e}: got #{got} exp #{exp}"
    end

    it = first.step(to: limit, by: step, exclusive: excl).as(SI)
    gotf = RH.first_from(it, e)
    expf = actual.select { |v| v >= e }.min?
    checks += 1
    if gotf != expf
      fails += 1
      puts "first_from MISMATCH #{first} #{limit} #{step} #{excl} e=#{e}: got #{gotf.inspect} exp #{expf.inspect}"
    end
  end
end

puts "T10 done: #{checks} checks, #{fails} failures"
