require "net/http"

class AzureOcrService
  @account_name = ENV["AZURE_STORAGE_NAME"]
  @account_key = ENV["AZURE_STORAGE_ACCESS_KEY"]
  @container_name = ENV["AZURE_STORAGE_CONTAINER"]
  @computer_vision_key = ENV["AZURE_COMPUTER_VISION_KEY"]
  @computer_vision_endpoint = ENV["AZURE_COMPUTER_VISION_ENDPOINT"]

  def self.ocr(document_url)
    uri = URI("https://eastus.api.cognitive.microsoft.com/vision/v3.2/read/analyze")
    uri.query = URI.encode_www_form({
 # Request parameters
           # "language" => "{string}",
           # "pages" => "{string}",
           # "readingOrder" => "{string}",
           # "model-version" => "{string}",
      })

    request = Net::HTTP::Post.new(uri.request_uri)
    # Request headers
    request["Content-Type"] = "application/json"
    # Request headers
    request["Ocp-Apim-Subscription-Key"] = @computer_vision_key
    # Request body
    request.body = { :url => @document_url }.to_json

    response = Net::HTTP.start(uri.host, uri.port, :use_ssl => uri.scheme == "https") do |http|
      http.request(request)
    end

    puts response.body

    # request = Net::HTTP::Post.new(uri.request_uri)
    # # Request headers
    # request["Content-Type"] = "application/json"
    # # Request headers
    # request["Ocp-Apim-Subscription-Key"] = @computer_vision_key
    # # Request body
    # request.body = { :url => "https://intelligentkioskstore.blob.core.windows.net/visionapi/suggestedphotos/3.png" }.to_json

    # response = Net::HTTP.start(uri.host, uri.port, :use_ssl => uri.scheme == "https") do |http|
    #   http.request(request)
    # end

    # puts response.body

    # puts @document_url
    # # response = RestClient.post "https://eastus.api.cognitive.microsoft.com/vision/v3.2/ocr", { :url => @document_url }.to_json, { content_type: :json, accept: :json, "Ocp-Apim-Subscription-Key": @computer_vision_key }
    # response = RestClient.post "https://eastus.api.cognitive.microsoft.com/vision/v3.2/read/analyze", { :url => @document_url }.to_json, { content_type: :json, accept: :json, "Ocp-Apim-Subscription-Key": @computer_vision_key }
    # puts response
  end
end
