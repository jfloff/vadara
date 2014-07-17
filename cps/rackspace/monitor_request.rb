require 'json'

module RackspaceVadara
  class MonitorRequest
    attr_accessor :metric_name, :statistics, :start_time, :end_time, :period, :detail

    def initialize(*args)
      # if argument was passed it is a json
      if args.length == 1
        self.from_json! args[0]
      end
    end

    def from_json!(json)
      json.each do |var, val|
        var = '@' + var
        self.instance_variable_set var, val
      end

      # translate statistics to rackspace
      @statistics.map! do |statistic|
        if statistic == 'avg'
          'average'
        else
          statistic
        end
      end

      @start_time = Time.at(@start_time)
      @end_time = Time.at(@end_time)
    end
  end
end
