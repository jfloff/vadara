require 'require_all'
require 'json'

module RackspaceVadara
  class ScalerRequest
    attr_accessor :horizontal_scale_up, :horizontal_scale_down

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

      if (defined?('horizontal_scale_up')).nil? or @horizontal_scale_up.nil?
        @horizontal_scale_up = 0
      elsif @horizontal_scale_up.has_key? 'rackspace'
        @horizontal_scale_up = @horizontal_scale_up['rackspace']
      else
        0
      end

      if (defined?('horizontal_scale_down')).nil? or @horizontal_scale_down.nil?
        @horizontal_scale_down = []
      elsif @horizontal_scale_down.has_key? 'rackspace'
        @horizontal_scale_down = @horizontal_scale_down['rackspace']
      else
        []
      end

    end
  end
end
