module Crystime
  # Collection of helpers independent of VirtualTime or Item,
  # and which work solely based on their input parameters.
  module Helpers
    # Wraps object in an Array if it is not an Array already.
    def self.force_array( arg)
      if !arg.is_a? Array
        [arg]
      else
        arg
      end
    end

    # Replaces any values of 'true' with a list of VTs. By default, the list is emtpy.
    def self.virtual_dates( list, default_list= [] of Crystime::VirtualTimeOrTime)
      list= force_array list
      di= list.index( true)
      if di
        list= list.dup
        list[di..di]= default_list
      end
      list
    end

    # Maps days of week to integers and vice-versa, and provides a regex for scanning for them in strings.
    W2I= { "SUN" => 0, "MON" => 1, "TUE" => 2, "WED" => 3, "THU" => 4, "FRI" => 5, "SAT" => 6}
    I2W= W2I.invert
    WR = Regex.new "\\b("+ W2I.keys.map(&->Regex.escape(String)).join('|')+ ")\\b"


    # Maps months to integers and vice-versa, and provides a regex for scanning for them in strings.
    M2I= { "JAN" => 1, "FEB" => 2, "MAR" => 3, "APR" => 4, "MAY" => 5, "JUN" => 6, "JUL" => 7, "AUG" => 8, "SEP" => 9, "OCT" => 10, "NOV" => 11, "DEC" => 12}
    I2M= M2I.invert
    MR = Regex.new "\\b("+ M2I.keys.map(&->Regex.escape(String)).join('|')+ ")\\b"

    # Scans for day of week name mentioned in string, and if found, returns that name.
    def self.find_day_of_week( str)
      str.scan(WR) do |m| return m[0] end
      nil
    end
    # Scans for month name mentioned in string, and if found, returns that name.
    def self.find_month( str)
      str.scan(MR) do |m| return m[0] end
      nil
    end

    # Compares all types of accepted values for T and/or VT against each other.
    def self.compare( a : Enumerable(Int), b : Enumerable(Int))
      a_set= a.dup.to_set
      b.all?{ |i| a_set.includes? i}
    end
    def self.compare( a : Proc(Int32, Bool), b : Int) a.call(b) end
    def self.compare( a : Int, b : Proc(Int32, Bool)) compare(b, a) end
    def self.compare( a : Enumerable(Int), b : Int) a.dup.includes? b end
    def self.compare( a : Nil, b) true end
    def self.compare( a, b : Nil) true end
    def self.compare( a : Int, b : Enumerable(Int)) compare(b, a) end
    def self.compare( a, b) a== b end

    # Checks if rule matches value, i.e. if value satisfies rule.
    # Matching rules:
    # 1. Nil matches all it is compared with
    # 1. Number matches that number
    # 1. Block matches if it returns true when executed
    # 1. Enumerable (including Range) matches if rule.includes?(value) is true
    # XXX throw Undeterminable if one asks for day match on date with no year, so days_in_month can't be calcd.
    # Fold is the starting value for negative numbers. You set it to days_in_month + 1. (E.g. if you want to wrap around 31st, you pass 32 as fold value.)
    #                 "DUE", "DATE"
    def self.check( rule, value, fold= nil)
      ret= compare( rule, value)

      if !ret && fold && value.is_a?( Int)
        # try once again, folding the test value around the specified point.
        # Careful with e.g. day<7 conditions, need to be translated to 1..7
        ret= check rule, value-fold, nil
      end

      #puts rule.inspect, value.inspect, ret
      ret
    end

    # Checks if any item in `list` matches the date part of `target`
    def self.matches_date?( target, list, default= true)
      return default if !list || (list.size==0)
      y, m= target.year, target.month
      if y.is_a? Int && m.is_a? Int
        dayfold= Time.days_in_month( y, m)+ 1
      end
      list.each do |e|
        return true if check( e.year, target.year) &&
          check( e.month, target.month) &&
          check( e.day, target.day, dayfold) &&
          check( e.day_of_week, target.day_of_week) #&&
          # Remove checking of #jd for now. First, this check is redundant
          # since in the current code jd can't get out of sync with Ymd.
          # Second, because removing this makes it possible to pass Time
          # objects through this method.
          #check( e.jd, target.jd)
      end
      nil
    end
    # Checks if any item in `list` matches the time part of `target`
    def self.matches_time?( target, list, default= true)
      return default if !list || (list.size==0)
      list.each do |e|
        return true if check( e.hour, target.hour) &&
          check( e.minute, target.minute) &&
          check( e.second, target.second) &&
          check( e.millisecond, target.millisecond)
      end
      nil
    end
    # Checks if any item in `list` matches `target`
    def self.matches?( target, list, default= true)
      matches_date?(target, list, default) &&
      matches_time?(target, list, default)
    end
  end
end
