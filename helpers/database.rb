require 'influxdb'

class Database
  def initialize
    raise NotImplementedError, "Implement this method in a child class"
  end
end