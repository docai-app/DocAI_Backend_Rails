# app/services/notion_service.rb

require 'net/http'
require 'uri'
require 'json'

class NotionService
  NOTION_API_URL = 'https://api.notion.com/v1'
  NOTION_API_VERSION = '2022-06-28'

  def initialize(token: ENV['NOTION_API_TOKEN'], database_id: ENV['NOTION_DATABASE_ID'])
    @token = token
    @database_id = database_id
  end

  def self.connect_db(domain)
    gateway = nil
    local_port = nil

    gateway, local_port = SshTunnelService.open(domain, 'akali', 'akl123123')
      
    if gateway.nil? || local_port.nil?
      return { error: "SSH tunnel setup failed" }
    end
    
    # 使用 PG 库直接连接到 PostgreSQL 数据库
    conn = PG.connect(
      dbname: 'dify',
      user: 'postgres',
      password: 'difyai123456',
      host: 'localhost',
      port: local_port
    )

    [conn, gateway, local_port]
  end

  def self.fetch_token_from_db(domain)
    begin
      conn, gateway, local_port = NotionService.connect_db(domain)
      sql = "select * from data_source_bindings where provider = 'notion' and disabled = false;"
      result = conn.exec_params(sql)
      result[0]['access_token']
    rescue => e
      { error: e.message }
    ensure
      conn.close if conn
      SshTunnelService.close(gateway) if gateway
    end
  end

  def list_all_pages(query = nil)
    uri = URI.parse("#{NOTION_API_URL}/search")
    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{@token}"
    request['Content-Type'] = 'application/json'
    request['Notion-Version'] = NOTION_API_VERSION

    request.body = {
      query: query,
      filter: { value: 'page', property: 'object' },
      sort: { direction: 'descending', timestamp: 'last_edited_time' }
    }.to_json

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end

    if response.code.to_i == 200
      JSON.parse(response.body)
    else
      puts "Error: #{response.message}"
      nil
    end
  rescue => e
    puts "Exception occurred: #{e.message}"
    nil
  end

  def create_page(parent_page_id, title, content)
    uri = URI.parse("#{NOTION_API_URL}/pages")
    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{@token}"
    request['Content-Type'] = 'application/json'
    request['Notion-Version'] = NOTION_API_VERSION

    request.body = {
      parent: { page_id: parent_page_id },
      properties: {
        title: {
          title: [
            {
              type: 'text',
              text: {
                content: title
              }
            }
          ]
        }
      },
      children: [
        {
          object: 'block',
          type: 'paragraph',
          paragraph: {
            rich_text: [
              {
                type: 'text',
                text: {
                  content: content
                }
              }
            ]
          }
        }
      ]
    }.to_json

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end

    JSON.parse(response.body)
  end

  def self.test_list_all_pages
    service = NotionService.new(token: "secret_ldZskmdnlpDXtCSmS3GONWWMSDwemP8cSTl8Snz4lEm")
    result = service.list_all_pages("pcm")
  
    if result && result['results']
      puts "Pages found: #{result['results'].size}"
      result['results'].each do |page|
        title = if page['properties'] && page['properties']['Name'] && page['properties']['Name']['title']
                  page['properties']['Name']['title'].map { |t| t['text']['content'] }.join
                else
                  "Untitled"
                end
        puts " - #{title} (ID: #{page['id']})"
      end
    else
      puts "No results found or an error occurred."
    end
  end

  def self.test
    service = new(token: "secret_ldZskmdnlpDXtCSmS3GONWWMSDwemP8cSTl8Snz4lEm", database_id: "c25ce0da11e14be18fdac0409bb5900d")
    title = "Test Page #{Time.now}"
    content = "This is a test page created at #{Time.now}."
    all_pages = NotionService.test_list_all_pages
    parent_page_id = all_pages.pluck("id").first #.gsub("-", "")
    # binding.pry
    response = service.create_page(parent_page_id, title, content)

    if response['object'] == 'page'
      puts "Success! Page created with ID: #{response['id']}"
    else
      puts "Error creating page: #{response['message']}"
    end
  end
end