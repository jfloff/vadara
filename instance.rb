require_relative "jsonable"
requite 'YAML'

class Instance < JSONable
  attr_accessor :image_id, :statistics, :start_time, :end_time, :period

  def initialize()
    config = YAML.load_file('config.yml')


  end
end
