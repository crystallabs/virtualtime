class Array
  # Expands ranges and other expandable types into a long list of all possible options.
  # E.g. [1, 2..3, 4..5] is expanded into [[1, 2, 4], [1,2, 5], [1,3,4], [1,3,5]].
  def expand
    Array.product map { |e|
      case e
      when Array
        e
      when Enumerable
        e.to_a
      else
        [e]
      end
    }
  end
end

struct Time
  def >( other : Crystime::VirtualTime)
    other< self
  end
  def <( other : Crystime::VirtualTime)
    (other> self)
  end
  def <=>( other : Crystime::VirtualTime)
    (other <=> self) * -1
  end
end
