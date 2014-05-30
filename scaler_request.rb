require_relative "jsonable"

class ScalerRequest < JSONable
  attr_accessor :scale_up, :scale_down
end
