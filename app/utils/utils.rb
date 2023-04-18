require "json"

class Utils
  def self.cleansingContentFromGPT(content)
    json_regex = /{[\s\S]*?}/m
    json_match = content.match(json_regex)

    if json_match
      json_str = json_match.to_s
      puts "json_str: #{json_str}"
      json_obj = JSON.parse(json_str)
      puts "json_obj: #{json_obj}"
      return json_obj
    else
      puts "No JSON found in the paragraph"
      return {}
    end

    return {}
  end
end
