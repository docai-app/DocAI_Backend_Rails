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

  def self.matchingKeys?(base_structure, comparison_structure)
    # Extract keys from both base_structure and comparison_structure
    base_keys = base_structure.keys
    comparison_keys = comparison_structure.keys

    puts "base_keys: #{base_keys}"
    puts "comparison_keys: #{comparison_keys}"

    # Check if the two key sets are equal
    base_keys.sort == comparison_keys.sort
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

  # Extract tenant name from JWT token or API key
  def self.extractRequestTenantByToken(request)
    if request.headers['Authorization'].present?
      apiToken = request.headers['Authorization']&.split(' ')&.last
      jwtPayload = decodeToken(apiToken)

      return unless apiToken && jwtPayload

      subdomain = jwtPayload['email'].split('@').last.split('.').first
      getTenantName(subdomain)
    elsif request.headers['X-API-KEY'].present?
      x_api_key = request.headers['X-API-KEY']
      api_key = ApiKey.active.find_by(key: x_api_key)
      tenant_name = api_key.tenant
      Apartment::Tenant.switch!(tenant_name)
      @current_user = api_key.user
      tenant_name
    end
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

  def self.encrypt(value)
    Base64.encode64(value.to_s)
  end

  def self.determine_file_type(file_url)
    file_type = File.extname(URI.parse(file_url).path).delete('.') # Delete the dot, only leave the extension
    file_type || 'unknown'
  end

  def self.calculate_file_size(file)
    File.size(file.path)
  end

  def self.calculate_file_size_by_url(url)
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    request = Net::HTTP::Get.new(uri)
    http.request(request).body.bytesize
  end
end
