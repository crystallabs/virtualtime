module Crystime

  # Group of module-level methods that return common Error objects for use in `raise`.
  # This method of doing it is just a convenience at the moment; it may be changed to
  # something else in the future.
  module Errors

    # Error when trying to compare partial VirtualTimes.
    def self.virtual_comparison( text= nil); ArgumentError.new \
      "Comparing VirtualTimes containing non-Int values not supported. Need to expand() your virtual date? (#{text})" end

    # Error when trying to compare uncomparable types.
    def self.unsupported_comparison( text= nil); ArgumentError.new \
      "Comparing these types not supported. It might be in the future. (#{text})" end

    # Error when unable to parse Julian Day Number.
    def self.invalid_jd( text= nil); ArgumentError.new \
      "Cannot parse invalid Julian Day Number. (#{text})" end

    # Error when trying to compare dates whose start/end times are not part of range.
    def self.exclusive_range_comparison( text= nil); ArgumentError.new \
      "Comparing exclusive ranges not supported. It will be in the future. (#{text})" end

    # Error for incorrect input.
    def self.incorrect_input( text= nil); ArgumentError.new \
      "Incorrect input or input format. (#{text})" end

    # Error for incorrect YAML input.
    def self.invalid_yaml_input( text= nil); ArgumentError.new \
      "Invalid YAML input. (#{text})" end

    # Error for nonexistent comparator between types.
    def self.no_comparator( a, b); ArgumentError.new \
      "No comparator defined between #{a.class} and #{b.class}." end

    # Error when VT can't be materialized due to some values being non-materializable.
    def self.cant_materialize( text= nil); ArgumentError.new \
      "Non-materializable values found. Materialization not supported (yet?). (#{text})" end
  end
end
