require 'require_all'
require_rel 'helpers/jsonable'

class ScalerRequest < JSONable
  attr_accessor :scale_up, :scale_down
end
