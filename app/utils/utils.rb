require "JSON"

class Utils
  def self.cleansingContentFromGPT(content)
    json_regex = /{.*}/m
    json_match = content.match(json_regex)

    puts "json_match: #{json_match}"

    if json_match
      json_str = json_match.to_s.gsub('\n', '\\n')
      puts "json_str: #{json_str}"
      json_obj = JSON.parse(json_str)
      return json_obj
    else
      puts "No JSON found in the paragraph"
      return {}
    end

    return {}
  end
end
