module Crystime
  class Item

    #@@default_omit= [] of VirtualDate
    #@@default_time= 43200 # Noon of given day

    property :start, :stop, :due, :omit, :omit_shift, :shift #, :remind, :omit_remind

    # Absolute start date/time. Item is never "on" before this date.
    @start : Nil | VirtualDate
    # Absolute stop date/time. Item is never "on" after this date.
    @stop  : Nil | VirtualDate
    #@time_ssm= 0.0 # XXX set to nil or something

    # List of VirtualDates on which the item is "on".
    @due = [] of VirtualDate
    # List of VirtualDates which should be "omitted", i.e. VirtualDates on which the item can't be "on".
    @omit= [] of VirtualDate
    # Action to take if item is due on an omitted date/time. Possible values are:
    # - nil: treat the item as non-applicable/not-scheduled on the specified date/time
    # - false: treat the item as not due because we are unable to (re)schedule it to any other date/time
    # - true: treat the item as due regardless of falling on an omitted date/time
    # - Time::Span: shift the scheduled date/time by specified time span. Can be negative (for
    # rescheduling before the original due) or positive (for rescheduling after the original due)).
    # Shifting is performed until a suitable date/time is found, or until max. number of shift
    # attempts is reached.
    @omit_shift : Nil | Bool | Crystime::Span
    @omit_shift= false
    # List of VirtualDates which item must match, after it was shifted due to omit, to be considered "on".
    @shift= [] of VirtualDate

    #@remind = [] of Nil | Wrap::Date | Wrap::Time | Wrap::DateTime | Time
    #@omit_remind

    # Custom getters / setters

    #def ssm() @time_ssm || @default_time end
    #def time( date= Time.now) Time.new(date)+ ssm end
    #def hour() Int32.new(ssm/ 3600) end
    #def minute() Int32.new((ssm% 3600)/ 60) end
    #def second() ssm% 60 end

    # Main functions intended for public use

    # TODO: non-interruptible/non-shareable tasks (just a flag)
    # all existing items should be in @omit when checking if term is free

    # TODO Add on? which works with Time objects

    # Checks whether the item is "on" on the specified date/time. Item is
    # considered "on" if it matches at least one "due" time and does not
    # match any "omit" time. If it matches an omit time, then depending on
    # the value of omit_shift it may still be "on", or attempted to be
    # rescheduled.
    # Return values are:
    # nil - item is not "on" / not "due"
    # true - item is "on" (it is "due" and not on "omit" list)
    # false - item is due, but that date is omitted, and no reschedule was requested or possible, so effectively it is not "on"
    # Time::Span - span which is to be added to asked date to reach the closes time when item is "on"
    def on?( date= VirtualDate.now, max_before= nil, max_after= max_before, max_shifts= 1000)
      d= date
      return unless d

      yes= due_on? d
      no=  omit_on? d
      #puts self.inspect
      #puts d.inspect
      #puts "#{yes}/#{no}"
      if yes
        if !no
          true
        else # check for shifting due to @omit:
          #puts "Going into omit search"
          omit_shift= @omit_shift
          if omit_shift.is_a? Nil | Bool
            omit_shift
          elsif omit_shift.total_milliseconds== 0
            #p "No shift"
            false
          else # Here omit_shift is virtualdate
            #puts "Some shift from #{d}"
            # +1=>search into the future, -1=>search into the past
            od= d.dup
            if d.is_a? Crystime::VirtualDate
              od.ts= d.ts.dup
            end
            #puts od.class
            #return true
            return if !od
            span= omit_shift
            #p span.inspect
            # Counter of times we've tried shifting.
            shifts= 0
            ret= loop do
              #p :in
              shifts+= 1
              #p od.inspect
              #p span.inspect
              if od.is_a? Crystime::VirtualDate
                od+= span
              else
                od+= span.span
              end
              #p "AFTER +: "+ od.inspect
              if (max_before&& ((od-d).total_milliseconds.abs> max_before.total_milliseconds)) ||
               (max_after&& ((od-d).total_milliseconds.abs> max_after.total_milliseconds)) ||
                (max_shifts&& (shifts> max_shifts))
                #puts shifts
                #puts od.inspect
                #puts @shift.inspect
                break false
              end
              if omit_on? od
                #puts "This AFTER date is omitted"
                next
              elsif due_on? od, @shift
                #puts od.inspect
                break true
              end
              #puts "didn't match: "+ od.inspect
              #puts "to: "+ @shift.inspect
            end
            #puts "d: #{d.inspect}, od: #{od.inspect}"
            #puts (od-d).inspect
            #puts ret.inspect
            #puts od.class
            #puts d.class
            #puts od.inspect
            return ret ? (od-d) : ret
          end
        end
      end
    end

#   def remind_on?( date= Time.now)
#     d= date
#     # separate reminders in absolute and relative
#     abs= @remind.select{|x| x.is_a? Wrap::Date | Wrap::Time | Wrap::DateTime | Time}
#     rel= @remind- abs
#     # see if there is an absolute match
#     abs.select!{ |x| x== d}
#     #abs.map!{ |x| x.respond_to? :hour ? x : "XXX no dice" } # XXX we assume all respond to hour
#     # test for on? on each date-reminder
#     rel.map! do |x|
#       unless x.is_a? ::Time::Span
#         x
#       else
#         ## negative difference x means in advance/before
#         ## we are catching everything between 0 and 24 h that day:
#         ## check and reverse check:
#         d00= d - 1.day - x.epoch
#         d24= (d+1.day) - 1.day - x.epoch
#         t= nil
#         if on? d00
#           t= d00 + x
#           t= nil unless d== t
#         end
#         if !t and on? d24
#           t= d24 + x
#           t= nil unless d== t
#         end
#         t
#       end
#     end
#     rel.compact!
#     abs+rel
#   end

    # Lower-level date/time testers

    # ```
    # it "uses negative numbers to count from end of month" do
    #   i= Crystime::Item.new
    #   due= Crystime::VirtualDate.new
    #   due.year= 2017
    #   due.month= 2
    #   due.day= -1
    #   i.due<< due
    #   date= Crystime::VirtualDate.new
    #   date.year= 2017
    #   date.month= 2
    #   date.day= 28
    #   i.due_on?( date).should eq true
    # end
    # ```

    def due_on?( target, list= @due)
      due_on_date?( target, list) &&
      due_on_time?( target, list)
    end
    def due_on_date?( target, list= @due)
      #puts "DD: "+ target.inspect, "\nLIST"+ list.inspect
      return if !target
      a, z= @start, @stop
      return nil if a &&( a> target)
      return nil if z &&( z< target)
      list= Crystime::Helpers.virtual_dates list
      Helpers.check_date( target, list, true)
    end
    def due_on_time?( target, list= @due)
      return if !target
      list= Crystime::Helpers.virtual_dates list
      Helpers.check_time( target, list, true)
    end

    def omit_on?( target)
      omit_on_date?( target) &&
      omit_on_time?( target)
    end
    def omit_on_date?( target)
      return if !target
      a, z= @start, @stop
      return nil if a &&( a> target)
      return nil if z &&( z< target)
      list= Crystime::Helpers.virtual_dates @omit
      Helpers.check_date( target, list, nil) # XXX, @@default_omit
    end
    def omit_on_time?( target)
      return if !target
      list= Crystime::Helpers.virtual_dates @omit
      Helpers.check_time( target, list, nil)
    end

    # Helpers below

#   def parse_timeunit( str)
#     s= str.upcase
#     case s
#     when "S" then 0
#     when "M" then 60
#     when "H" then 3600
#     when "D" then 3600*24
#     when "W" then 3600*24*7
#     else raise ArgumentError.new "Unknown time unit: #{s}"
#     end
#   end
#
#   def time=( time)
#      @time_ssm= nil
#      case time
#        when Array
#          time[0]* 3600+ time[1]* 60+ time[2]
#        when Time
#          time.hour* 3600+ time.minute* 60+ time.second
#        else nil
#      end
#    end
  end
end
