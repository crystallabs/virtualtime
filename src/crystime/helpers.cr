module Crystime
  # Collection of helpers independent of VirtualDate or Item,
  # and which work solely based on their input parameters.
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

    # Checks if rule matches value, i.e. if value satisfies rule.
    # Matching rules:
    # 1. Nil matches all it is compared with
    # 1. Number matches that number
    # 1. Block matches if it returns true when executed
    # 1. Enumerable (including Range) matches if rule.includes?(value) is true
    # XXX throw Undeterminable if one asks for day match on date with no year, so days_in_month can't be calcd.
    #                 "DUE", "DATE"
    def self.matches?( rule, value, fold= nil)
      # Fold is the starting value for negative numbers
      ret= compare( rule, value)

      # XXX This code should be re-enabled and then tests written for it.
      #if fold && !ret && value.is_a?( Int)
      #  # try once again, folding the test value around the specified point.
      #  # Careful with e.g. day<7 conditions, need to be translated to 1..7
      #  ret= matches? rule, value-fold, nil
      #end

      #puts rule.inspect, value.inspect, ret
      ret
    end

    # Checks if the date part of `target` matches any items in `list`.
    def self.check_date( target, list, default= true)
      #puts "checking #{list.inspect} re. #{target.inspect}"
      return default if !list || (list.size==0)
      y, m= target.year, target.month
      if y.is_a? Int && m.is_a? Int
        dayfold= Time.days_in_month( y, m)+ 1
      end
      list.each do |e|
        #puts :IN, e.inspect, target.inspect
        return true if matches?( e.year, target.year) &&
          matches?( e.month, target.month) &&
          matches?( e.day, target.day, dayfold) &&
          matches?( e.day_of_week, target.day_of_week) #&&
          # Remove checking of #jd for now. First, this check is redundant
          # since in the current code jd can't get out of sync with Ymd.
          # Second, because removing this makes it possible to pass Time
          # objects through this method.
          #matches?( e.jd, target.jd)
      end
      nil
    end
    # Checks if the time part of `target` matches any items in `list`.
    def self.check_time(  target, list, default= true)
      return default if !list || (list.size==0)
      list.each do |e|
        return true if matches?( e.hour, target.hour) &&
          matches?( e.minute, target.minute) &&
          matches?( e.second, target.second) &&
          matches?( e.millisecond, target.millisecond)
      end
      nil
    end
  end
end
