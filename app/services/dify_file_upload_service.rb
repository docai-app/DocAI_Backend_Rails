# frozen_string_literal: true

require 'rest-client'

# Service to handle Dify file upload workflow
# Implements the two-step process: upload file first, then use upload_file_id in workflow
class DifyFileUploadService
  # Dify API configuration
  API_BASE_URL = 'https://aienglish-dify.docai.net/v1'
  UPLOAD_ENDPOINT = "#{API_BASE_URL}/files/upload"
  TIMEOUT = 60 # seconds

  # File upload result structure
  Result = Struct.new(:success?, :upload_file_id, :error_message, keyword_init: true)

  def initialize(app_key, user_id)
    @app_key = app_key
    @user_id = user_id
    @logger = Rails.logger
  end

  # Upload a file from URL to Dify and get upload_file_id
  def upload_from_url(file_url, file_type = 'image')
    @logger.info("[DifyFileUploadService] Starting file upload from URL: #{file_url}")

    begin
      # Download file from URL first
      downloaded_file = download_file_from_url(file_url)
      return Result.new(success?: false, error_message: 'Failed to download file from URL') unless downloaded_file

      # Upload to Dify
      upload_result = upload_file_to_dify(downloaded_file, file_type)

      # Cleanup temp file
      downloaded_file.close
      downloaded_file.unlink

      upload_result
    rescue StandardError => e
      @logger.error("[DifyFileUploadService] Unexpected error: #{e.message}")
      Result.new(success?: false, error_message: "Upload failed: #{e.message}")
    end
  end

  # Upload a file directly to Dify (for files already available as File objects)
  def upload_file(file, file_type = 'image')
    @logger.info('[DifyFileUploadService] Starting direct file upload')
    upload_file_to_dify(file, file_type)
  end

  private

  # Download file from URL to a temporary file
  def download_file_from_url(file_url)
    @logger.info("[DifyFileUploadService] Downloading file from URL: #{file_url}")

    uri = URI(file_url)

    # 檢查URL中的文件擴展名
    url_extension = File.extname(uri.path)
    @logger.info("[DifyFileUploadService] URL file extension: #{url_extension}")

    response = RestClient::Request.execute(
      method: :get,
      url: file_url,
      timeout: TIMEOUT
    )

    # 從響應頭中獲取 Content-Type
    content_type = response.headers[:content_type] || response.headers['content-type']
    @logger.info("[DifyFileUploadService] Response Content-Type: #{content_type}")
    @logger.info("[DifyFileUploadService] Response size: #{response.body.bytesize} bytes")

    # 確定文件擴展名
    file_extension = determine_file_extension(content_type, url_extension)
    @logger.info("[DifyFileUploadService] Determined file extension: #{file_extension}")

    # 先確定真實的文件類型
    header = response.body[0, 20]
    actual_extension = determine_extension_from_header(header)
    if actual_extension
      file_extension = actual_extension
      @logger.info("[DifyFileUploadService] Corrected file extension based on header: #{file_extension}")
    end

    # 創建帶有正確擴展名的臨時文件
    temp_file = Tempfile.new(['dify_upload', file_extension])
    temp_file.binmode
    temp_file.write(response.body)
    temp_file.rewind

    # 驗證文件內容是否為有效圖片
    if file_extension.match?(/\.(jpg|jpeg|png|gif|webp)$/i) && !valid_image_file?(temp_file)
      @logger.error('[DifyFileUploadService] Downloaded file is not a valid image')
      temp_file.close
      temp_file.unlink
      return nil
    end

    @logger.info("[DifyFileUploadService] File downloaded successfully, temp file: #{temp_file.path}")
    temp_file
  rescue StandardError => e
    @logger.error("[DifyFileUploadService] Failed to download file from URL #{file_url}: #{e.message}")
    @logger.error("[DifyFileUploadService] Error backtrace: #{e.backtrace.first(5).join('\n')}")
    nil
  end

  # 根據文件頭確定擴展名
  def determine_extension_from_header(header)
    case header
    when /^\xff\xd8\xff/n # JPEG
      '.jpg'
    when /^\x89PNG\r\n\x1a\n/n # PNG
      '.png'
    when /^GIF8[79]a/n # GIF
      '.gif'
    when /^RIFF....WEBP/n # WebP
      '.webp'
    end
  end

  # 根據 Content-Type 和 URL 擴展名確定文件擴展名
  def determine_file_extension(content_type, url_extension)
    # 首先嘗試根據 Content-Type 確定
    case content_type.to_s.downcase
    when %r{image/jpeg}, %r{image/jpg}
      '.jpg'
    when %r{image/png}
      '.png'
    when %r{image/gif}
      '.gif'
    when %r{image/webp}
      '.webp'
    when %r{image/svg}
      '.svg'
    else
      # 如果 Content-Type 不明確，使用 URL 擴展名
      if url_extension.present? && url_extension.match?(/\.(jpg|jpeg|png|gif|webp|svg)$/i)
        url_extension
      else
        # 默認為 .jpg
        '.jpg'
      end
    end
  end

  # 簡單的圖片文件驗證
  def valid_image_file?(file)
    file.rewind
    header = file.read(20)
    file.rewind

    # 檢查常見圖片格式的文件頭
    # 創建二進制字符串來比較，避免修改凍結字符串
    jpeg_header = "\xFF\xD8\xFF".b
    png_header = "\x89PNG\r\n\x1a\n".b
    gif_header1 = 'GIF87a'.b
    gif_header2 = 'GIF89a'.b

    case header
    when /^\xff\xd8\xff/n # JPEG
      true
    when /^\x89PNG\r\n\x1a\n/n # PNG
      true
    when /^GIF8[79]a/n # GIF
      true
    when /^RIFF....WEBP/n # WebP
      true
    else
      # 如果文件頭不匹配，但內容不為空，可能仍然是有效的圖片
      header.bytesize > 0
    end
  end

  # Upload file to Dify and return upload_file_id
  def upload_file_to_dify(file, file_type)
    @logger.info('[DifyFileUploadService] Uploading file to Dify')

    # 記錄文件詳細信息
    @logger.info("[DifyFileUploadService] File path: #{file.path}")
    @logger.info("[DifyFileUploadService] File size: #{file.size} bytes")

    # 根據文件類型確定正確的文件名和 MIME 類型
    filename, content_type = determine_file_details(file, file_type)
    @logger.info("[DifyFileUploadService] Determined filename: #{filename}")
    @logger.info("[DifyFileUploadService] Determined content_type: #{content_type}")

    # 確保文件指針在開始位置
    file.rewind

    # Prepare multipart form data - 讓 RestClient 自動處理 Content-Type
    payload = {
      file:,
      user: @user_id,
      type: determine_dify_file_type(file_type)
    }

    @logger.info("[DifyFileUploadService] Upload payload - user: #{@user_id}, type: #{determine_dify_file_type(file_type)}")

    response = RestClient::Request.execute(
      method: :post,
      url: UPLOAD_ENDPOINT,
      payload:,
      headers: upload_headers,
      timeout: TIMEOUT
    )

    @logger.info("[DifyFileUploadService] Upload response status: #{response.code}")
    @logger.info("[DifyFileUploadService] Upload response body: #{response.body}")

    if response.code == 201
      result = JSON.parse(response.body)
      upload_file_id = result['id']

      @logger.info("[DifyFileUploadService] File uploaded successfully, upload_file_id: #{upload_file_id}")
      Result.new(success?: true, upload_file_id:)
    else
      @logger.error("[DifyFileUploadService] Upload failed with status: #{response.code}")
      @logger.error("[DifyFileUploadService] Response body: #{response.body}")
      Result.new(success?: false, error_message: "Upload failed with status: #{response.code}")
    end
  rescue RestClient::ExceptionWithResponse => e
    @logger.error("[DifyFileUploadService] API request failed: #{e.response}")
    @logger.error("[DifyFileUploadService] Error message: #{e.message}")
    Result.new(success?: false, error_message: 'Failed to upload file to Dify API')
  rescue JSON::ParserError => e
    @logger.error("[DifyFileUploadService] Failed to parse API response: #{e.message}")
    Result.new(success?: false, error_message: 'Invalid response from Dify API')
  rescue StandardError => e
    @logger.error("[DifyFileUploadService] Unexpected error during upload: #{e.message}")
    @logger.error("[DifyFileUploadService] Error backtrace: #{e.backtrace.first(5).join('\n')}")
    Result.new(success?: false, error_message: "Upload failed: #{e.message}")
  end

  # 根據文件內容和類型確定文件名和 Content-Type
  def determine_file_details(file, _file_type)
    file.rewind
    header = file.read(20)
    file.rewind

    # 根據文件頭確定真實的文件類型
    case header
    when /^\xff\xd8\xff/n # JPEG
      filename = "image_#{SecureRandom.hex(8)}.jpg"
      content_type = 'image/jpeg'
    when /^\x89PNG\r\n\x1a\n/n # PNG
      filename = "image_#{SecureRandom.hex(8)}.png"
      content_type = 'image/png'
    when /^GIF8[79]a/n # GIF
      filename = "image_#{SecureRandom.hex(8)}.gif"
      content_type = 'image/gif'
    when /^RIFF....WEBP/n # WebP
      filename = "image_#{SecureRandom.hex(8)}.webp"
      content_type = 'image/webp'
    else
      # 如果無法識別，默認為 JPEG
      filename = "image_#{SecureRandom.hex(8)}.jpg"
      content_type = 'image/jpeg'
    end

    [filename, content_type]
  end

  # Generate headers for upload request
  def upload_headers
    {
      'Authorization' => "Bearer #{@app_key}"
      # NOTE: Do NOT set Content-Type for multipart uploads, let RestClient handle it
    }
  end

  # Map file types to Dify's expected format
  def determine_dify_file_type(file_type)
    case file_type.to_s.downcase
    when 'image', 'jpg', 'jpeg', 'png', 'gif', 'webp', 'svg'
      'image'
    when 'document', 'pdf', 'txt', 'md', 'docx', 'xlsx'
      'document'
    when 'audio', 'mp3', 'm4a', 'wav'
      'audio'
    when 'video', 'mp4', 'mov'
      'video'
    else
      'custom'
    end
  end
end
