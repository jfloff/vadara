require 'json'

module RackspaceVadara
  class MonitorRequest
    attr_accessor :metric_name, :statistics, :start_time, :end_time, :points, :detail

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

      # time has to be in miliseconds
      @start_time = (Time.parse(@start_time).to_f * 1000).to_i
      @end_time = (Time.parse(@end_time).to_f * 1000).to_i

      # period comes in seconds, we have to find out how many points
      # that period translates to for rackspace API
      # http://docs.rackspace.com/cm/api/v1.0/cm-devguide/content/metrics-api.html#metrics-api-summary
      @points = (@end_time - @start_time) / (@period * 1000)
    end
  end
end
