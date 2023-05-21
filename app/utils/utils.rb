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

  def self.concatDocumentsContent(documents)
    content = ""
    documents.each_with_index do |document, index|
      content += "Document #{index + 1}: #{document.content}\t "
    end
    return content
  end

  def self.extractReferrerSubdomain(referrer)
    if referrer && referrer != "localhost"
      url = URI.parse(referrer)
      # Assuming that your url is in the format "http://subdomain.domain.com"
      subdomain = url.host.split(".").first
    elsif referrer == "localhost"
      subdomain = "chyb_dev"
    else
      subdomain = "chyb_dev"
    end
    return subdomain
  end
end
