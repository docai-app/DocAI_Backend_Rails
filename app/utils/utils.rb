# frozen_string_literal: true

require 'json'

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
      puts 'No JSON found in the paragraph'
      return {}
    end

    {}
  end

  def self.concatDocumentsContent(documents)
    content = ''
    documents.each_with_index do |document, index|
      content += "Document #{index + 1}: #{document.content}\t "
    end
    content
  end

  def self.extractReferrerSubdomain(referrer)
    if referrer && referrer != 'localhost'
      url = URI.parse(referrer)
      # Assuming that your url is in the format "http://subdomain.domain.com"
      subdomain = url.host.split('.').first
      subdomain = Apartment.tenant_names.include?(subdomain) ? subdomain : 'public'
    elsif referrer == 'localhost'
      subdomain = ENV.fetch('DEFAULT_TENANT_NAME', 'public')
    else
      subdomain = ENV.fetch('DEFAULT_TENANT_NAME', 'public')
    end
    subdomain
  end

  def self.extractRequestTenantByToken(request)
    apiToken = request.headers['Authorization']&.split(' ')&.last
    jwtPayload = decodeToken(apiToken)

    return unless apiToken && jwtPayload

    subdomain = jwtPayload['email'].split('@').last.split('.').first
    getTenantName(subdomain)
  end

  def self.decodeToken(token)
    jwtPayload = JWT.decode(token, ENV['DEVISE_JWT_SECRET_KEY']).first
    puts "jwt_payload: #{jwtPayload}"
    jwtPayload
  rescue StandardError => e
    puts e.message
  end

  def self.getTenantName(subdomain)
    Apartment.tenant_names.include?(subdomain) ? subdomain : 'public'
  end
end
