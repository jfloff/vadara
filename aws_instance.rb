require_relative "jsonable"

class MonitorRequest < JSONable
  attr_accessor :metric_name, :statistics, :start_time, :end_time, :period
end
