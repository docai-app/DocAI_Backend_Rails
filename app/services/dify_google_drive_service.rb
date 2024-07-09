# frozen_string_literal: true

# app/services/notion_service.rb

require 'net/http'
require 'uri'
require 'json'

class DifyGoogleDriveService
  NOTION_API_URL = 'https://api.notion.com/v1'
  NOTION_API_VERSION = '2022-06-28'

  def initialize(token: ENV['NOTION_API_TOKEN'])
    @token = token
  end

  def self.connect_db(domain)
    gateway, local_port = SshTunnelService.open(domain, 'akali', 'akl123123')

    return { error: 'SSH tunnel setup failed' } if gateway.nil? || local_port.nil?

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

  def self.insert_token_to_db(domain, workspace, token, dify_user_id)
    # 建立與數據庫的連接
    conn, gateway, = DifyGoogleDriveService.connect_db(domain)

    # 定義 SQL 查詢並參數化
    sql = <<-SQL
        INSERT INTO data_source_bindings (tenant_id, provider, access_token, source_info)
        VALUES (
          (SELECT id FROM tenants WHERE id = $1),#{' '}
          'personal_google_drive',#{' '}
          $2,#{' '}
          jsonb_build_object('dify_user_id', $3::text)
        )
    SQL

    puts "sql: #{sql}"

    # 執行查詢並傳遞參數
    conn.exec_params(sql, [workspace, token, dify_user_id])

    # 返回成功信息
    { success: true }
  rescue PG::Error => e
    # 返回錯誤信息
    puts "Error: #{e.message}"
    { error: e.message }
  ensure
    # 確保連接和 SSH 隧道被關閉
    conn&.close
    SshTunnelService.close(gateway) if gateway
  end

  def self.fetch_token_from_db(domain, workspace, dify_user_id)
    # 建立與數據庫的連接
    conn, gateway, = DifyGoogleDriveService.connect_db(domain)

    # 定義 SQL 查詢並參數化
    sql = <<-SQL
        SELECT data_source_bindings.access_token
        FROM data_source_bindings#{' '}
        INNER JOIN tenants ON tenants.id = data_source_bindings.tenant_id
        WHERE provider = $1#{' '}
          AND disabled = false#{' '}
          AND tenants.id = $2
          AND source_info->>'dify_user_id' = $3::text
    SQL

    # 執行查詢並傳遞參數
    result = conn.exec_params(sql, ['personal_google_drive', workspace, dify_user_id])

    # 返回訪問令牌
    result.ntuples.positive? ? result[0]['access_token'] : nil
  rescue PG::Error => e
    # 返回錯誤信息
    { error: e.message }
  ensure
    # 確保連接和 SSH 隧道被關閉
    conn&.close
    SshTunnelService.close(gateway) if gateway
  end

  def list_all_pages(query: nil, page_size: 25, direction: 'descending')
    uri = URI.parse("#{NOTION_API_URL}/search")
    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{@token}"
    request['Content-Type'] = 'application/json'
    request['Notion-Version'] = NOTION_API_VERSION

    request.body = {
      filter: { value: 'page', property: 'object' },
      sort: { direction:, timestamp: 'last_edited_time' },
      page_size:
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
                    'Untitled'
                  end

          puts " - #{title} (ID: #{page['id']})"
        end
      else
        puts 'No results found or an error occurred.'
      end
    else
      puts "Error: #{response.message}"
      nil
    end
  rescue StandardError => e
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
                  content:
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
  #   service = DifyGoogleDriveService.new(token: "secret_ldZskmdnlpDXtCSmS3GONWWMSDwemP8cSTl8Snz4lEm")
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
    service = new(token: 'secret_ldZskmdnlpDXtCSmS3GONWWMSDwemP8cSTl8Snz4lEm')
    title = "Test Page #{Time.now}"
    content = "This is a test page created at #{Time.now}."
    all_pages = DifyGoogleDriveService.test_list_all_pages
    parent_page_id = all_pages.pluck('id').first # .gsub("-", "")
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
    extract_parent_id(all_pages[0])
  end

  def extract_parent_id(page)
    parent = page['parent']
    case parent['type']
    when 'workspace'
      page['id']
    when 'page_id'
      parent['page_id']
    end
  end
end
