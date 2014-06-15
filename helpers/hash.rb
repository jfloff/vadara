class Hash

  def symbolize_keys
    self.inject({}){|result, (key, value)|
      new_key = case key
                when String then key.to_sym
                else key
                end
      new_value = case value
                  when Hash then value.symbolize_keys
                  when Array then value.map{ |v| v.is_a?(Hash) ? v.symbolize_keys : v }
                  else value
                  end
      result[new_key] = new_value
      result
    }
  end

end
