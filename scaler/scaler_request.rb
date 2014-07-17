require 'require_all'
require_all 'helpers/jsonable.rb'

module Vadara
  class ScalerRequest < JSONable
    attr_accessor :horizontal_scale_up, :horizontal_scale_down

    def initialize(*args)
      # if argument was passed it is a json
      if args.length == 1
        self.from_json! args[0]
      end
    end

  end
end
