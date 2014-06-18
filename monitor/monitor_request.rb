require 'require_all'
require_all 'helpers/jsonable.rb'

module Vadara
  class MonitorRequest < JSONable
    attr_accessor :metric_name, :statistics, :start_time, :end_time, :period, :detail

    def initialize(*args)
      # if argument was passed it is a json
      if args.length == 1
        self.from_json! args[0]
      end
    end
  end
end
