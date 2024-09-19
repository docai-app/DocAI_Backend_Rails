# frozen_string_literal: true

require 'rest-client'
require 'json'
require 'net/http'

class DifyService
  URL = ENV['DIFY_CHATBOT_URL'] || 'http://103.225.9.44:9888/v1/chat-messages'
  HEADERS = {
    'Content-Type' => 'application/json'
  }.freeze

  def initialize(user, query, conversation_id, dify_token)
    @user_id = user.id
    @user = user
    @query = query
    @conversation_id = conversation_id
    @bearer_token = dify_token
  end

  def prompt_wrapper
    DifyService.prompt_wrapper(@user, @query)
  end

  def self.prompt_wrapper(user, query)
    # 讀取 user 的必要資訊，附加過去
    chatbot_list = user.chatbots

    "可以使用的 chatbots:\n" \
    "====\n" \
    "#{chatbot_list}\n" \
    "====\n\n" \
    "我的資料如下:\n" \
    "====\n" \
    "user_id: #{user.id}\n" \
    "timezone: 'Asia/Hong_Kong'\n" \
    "====\n\n" \
    "query:\n" \
    "====\n" \
    "#{query}\n" \
    "====\n"
  end

  def self.test
    Apartment::Tenant.switch!('public')
    # @general_user = User.find('1665947b-a056-4bff-bdcf-34ecfa2667b9')
    @general_user = GeneralUser.find('6819cfe6-2cbd-4456-9a07-97cc1b6332df') # edison
    query = '你好'
    dify_token = 'app-CaqRv7KGzfkEu9s3Ti4kjKJx'

    # result = DifyService.new(@general_user, query, nil,  dify_token).send_request
    # puts result
    dy = DifyService.new(@general_user, query, nil, dify_token)
    binding.pry
    # dy.prompt_header
    dy
  end

  def send_request
    uri = URI(URL)
    req = Net::HTTP::Post.new(uri, headers_with_auth)
    req.body = request_body.to_json

    Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
      http.request(req) do |response|
        return handle_error(response) unless response.is_a?(Net::HTTPSuccess)

        result = handle_streaming_response(response)
        return result
      end
    end
  end

  private

  def handle_streaming_response(http_response)
    answer = ''
    conversation_id = nil

    http_response.read_body do |chunk|
      process_chunk(chunk) do |data|
        case data['event']
        when 'agent_message', 'message'
          answer += data['answer'].to_s
        when 'message_replace'
          answer = data['answer'].to_s
        when 'message_end'
          conversation_id = data['conversation_id']
        end
      end
    end

    {
      answer: answer.strip.empty? ? 'No answer received from the Chatbot' : answer.strip,
      conversation_id:
    }
  end

  def process_chunk(chunk)
    chunk.force_encoding('UTF-8').split("\n").each do |line|
      next if line.strip.empty?

      begin
        data = JSON.parse(line.strip.gsub(/^data: /, ''))
        yield data if block_given?
      rescue JSON::ParserError
        # Log or handle JSON parsing error appropriately
      end
    end
  end

  def headers_with_auth
    HEADERS.merge('Authorization' => "Bearer #{@bearer_token}")
  end

  def request_body
    {
      'inputs' => {},
      'query' => prompt_wrapper,
      'response_mode' => 'streaming',
      'user' => @user_id,
      'conversation_id' => @conversation_id
    }.compact
  end

  def handle_error(response)
    # Handle non-success responses
    puts "HTTP Error: #{response.code} - #{response.message}"
  end
end
