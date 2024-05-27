# app/services/notion_service.rb

require 'net/http'
require 'uri'
require 'json'

class NotionService
  NOTION_API_URL = 'https://api.notion.com/v1'
  NOTION_API_VERSION = '2022-06-28'

  def initialize(token: ENV['NOTION_API_TOKEN'])
    @token = token
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

  def self.fetch_token_from_db(domain, workspace)
    begin
      # 建立與數據庫的連接
      conn, gateway, local_port = NotionService.connect_db(domain)
  
      # 定義 SQL 查詢並參數化
      sql = <<-SQL
        SELECT data_source_bindings.access_token
        FROM data_source_bindings 
        INNER JOIN tenants ON tenants.id = data_source_bindings.tenant_id
        WHERE provider = $1 AND disabled = false AND tenants.name = $2
      SQL
  
      # 執行查詢並傳遞參數
      result = conn.exec_params(sql, ['notion', workspace])
  
      # 返回訪問令牌
      result.ntuples > 0 ? result[0]['access_token'] : nil
  
    rescue PG::Error => e
      # 返回錯誤信息
      { error: e.message }
  
    ensure
      # 確保連接和 SSH 隧道被關閉
      conn.close if conn
      SshTunnelService.close(gateway) if gateway
    end
  end

  def list_all_pages(query: nil, page_size: 25, direction: 'descending')
    uri = URI.parse("#{NOTION_API_URL}/search")
    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{@token}"
    request['Content-Type'] = 'application/json'
    request['Notion-Version'] = NOTION_API_VERSION

    request.body = {
      filter: { value: 'page', property: 'object' },
      sort: { direction: direction, timestamp: 'last_edited_time' },
      page_size: page_size
    }
    request.body[:query] = query if query.present?
    request.body = request.body.to_json

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end

    if response.code.to_i == 200
      result = JSON.parse(response.body)
      if result && (pages = result['results'])
        puts "Pages found: #{pages.size}"

        pages.each do |page|
          title_elements = page.dig('properties', 'title', 'title')
          title = if title_elements
                    title_elements.map { |t| t.dig('text', 'content') }.join
                  else
                    "Untitled"
                  end
          
          puts " - #{title} (ID: #{page['id']})"
        end
      else
        puts "No results found or an error occurred."
      end
    else
      puts "Error: #{response.message}"
      nil
    end
  rescue => e
    puts "Exception occurred: #{e.message}"
    nil
  end

  def create_page(title, content, parent_page_id = nil)
    uri = URI.parse("#{NOTION_API_URL}/pages")
    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{@token}"
    request['Content-Type'] = 'application/json'
    request['Notion-Version'] = NOTION_API_VERSION

    if parent_page_id.nil?
      begin
        parent_page_id = get_default_parent_page_id
      rescue NoMethodError
        return { success: false, message: 'no notion page is found' }, status: :unprocessable_entity
      end
    end

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

  # def self.test_list_all_pages
  #   service = NotionService.new(token: "secret_ldZskmdnlpDXtCSmS3GONWWMSDwemP8cSTl8Snz4lEm")
  #   result = service.list_all_pages("pcm")
  
  #   if result && (pages = result['results'])
  #     puts "Pages found: #{pages.size}"
      
  #     pages.each do |page|
  #       title_elements = page.dig('properties', 'title', 'title')
  #       title = if title_elements
  #                 title_elements.map { |t| t.dig('text', 'content') }.join
  #               else
  #                 "Untitled"
  #               end
        
  #       puts " - #{title} (ID: #{page['id']})"
  #     end
  #   else
  #     puts "No results found or an error occurred."
  #   end
  # end

  def self.test
    service = new(token: "secret_ldZskmdnlpDXtCSmS3GONWWMSDwemP8cSTl8Snz4lEm")
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

  def get_default_parent_page_id
    all_pages = list_all_pages(page_size: 1, direction: 'ascending')
    parent_page_id = extract_parent_id(all_pages[0])
  end

  def extract_parent_id(page)
    parent = page['parent']
    case parent['type']
    when 'workspace'
      page['id']
    when 'page_id'
      parent['page_id']
    else
      nil
    end
  end

end