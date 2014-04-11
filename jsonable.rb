# http://stackoverflow.com/a/4464721
class JSONable
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
