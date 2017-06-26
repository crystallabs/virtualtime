class Array
  # Adds a convenience method to Array class.
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
