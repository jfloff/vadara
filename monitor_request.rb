# metric_name: 'CPUUtilization',
# statistics: ['Average'],
# start_time: time-1000,
# end_time: time+1000,
#     period: 60,

require_relative "jsonable"

class MonitorRequest < JSONable
  attr_accessor :metric_name, :statistics, :start_time, :end_time, :period
end
