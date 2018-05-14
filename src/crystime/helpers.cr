module Crystime
  module Helpers
		# Wraps object in an Array if it is not an Array already.
    def self.force_array( arg)
      if !arg.is_a? Array
        return [arg]
      else
        return arg
      end
    end

		# Replaces any values of 'true' with a list of VDs. By default, the list is emtpy.
    def self.virtual_dates( list, default_list= [] of VirtualDate)
      list= force_array list
      di= list.index( true)
      if di
        list= list.dup
        list[di..di]= default_list
      end
      list
    end

		# Compares all 7 types of accepted values for a VD against each other.
    def self.compare( a : Enumerable(Int), b : Enumerable(Int))
      a_set= a.dup.to_set
      b.all?{ |i| a_set.includes? i}
    end
    def self.compare( a : Proc(Int32, Bool), b : Int) a.call(b) end
    def self.compare( a : Enumerable(Int), b : Int) a.dup.includes? b end
    def self.compare( a : Int, b : Int) a== b end
    def self.compare( a : Nil, b) true end
    def self.compare( a, b : Nil) true end
    def self.compare( a : Int, b : Enumerable(Int)) compare(b, a) end
    def self.compare( a, b)
      raise Crystime::Errors.no_comparator(a, b)
    end
  end
end
