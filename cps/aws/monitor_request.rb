require 'json'

module AwsVadara
  class MonitorRequest
    attr_accessor :metric_name, :statistics, :start_time, :end_time, :period

    def initialize(*args)
      # if argument was passed it is a json
      if args.length == 1
        self.from_json! args[0]
      end
    end

    def to_json
      hash = {}
      self.instance_variables.each do |var|
        hash[var[1..-1]] = self.instance_variable_get var
      end
      hash.to_json
    end

    def from_json!(json)
      json.each do |var, val|
        var = '@' + var
        self.instance_variable_set var, val
      end
    end
  end
end
