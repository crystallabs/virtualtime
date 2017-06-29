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
    # List of VirtualDates which item must match, after it was shifted due to omit, to be considered "on".
    @shift= [] of VirtualDate
    # Action to take if item is due on an omitted date/time. Possible values are:
    # - nil: treat the item as non-applicable/not-scheduled on the specified date/time
    # - false: treat the item as not due because we are unable to (re)schedule it to any other date/time
    # - true: treat the item as due regardless of falling on an omitted date/time
    # - Time::Span: the rescheduled date/time by specified time span (can be negative (for
    # rescheduling before the original due) or positive (for rescheduling after the original due))
    @omit_shift : Nil | Bool | Crystime::Span
    @omit_shift= false

    #@remind = [] of Nil | Wrap::Date | Wrap::Time | Wrap::DateTime | Time
    #@omit_remind

    # Custom getters / setters

    #def ssm() @time_ssm || @default_time end
    #def time( date= Time.now) Time.new(date)+ ssm end
    #def hour() Int32.new(ssm/ 3600) end
    #def minute() Int32.new((ssm% 3600)/ 60) end
    #def second() ssm% 60 end

  end
end
