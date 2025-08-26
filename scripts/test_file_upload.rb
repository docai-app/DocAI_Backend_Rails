#!/usr/bin/env ruby
# frozen_string_literal: true

# 測試腳本：驗證 Azure Blob Storage 文件下載和 Dify 上傳
require_relative '../config/environment'

# 測試 URL（使用實際的 Azure Blob Storage URL）
test_url = 'https://m2mda.blob.core.windows.net/chyb-document-storage/m7ks9zzocga6njwipda4abzr4t1i?sp=r&sv=2018-11-09&se=2025-06-13T19%3A06%3A56Z&rscd=inline%3B+filename%3D%22ielts-task-1-pie-chart.jpg%22%3B+filename*%3DUTF-8%27%27ielts-task-1-pie-chart.jpg&rsct=image%2Fjpeg&sr=b&sig=fq76hCBpV1m4c57mHYM0pGWQllfNZRF%2FdG0f50ly7NQ%3D'

puts '=== 測試 Azure Blob Storage 文件下載和 MIME 類型檢測 ==='
puts "測試 URL: #{test_url}"
puts

begin
  # 1. 測試直接下載文件
  puts '1. 直接下載文件...'
  response = RestClient::Request.execute(
    method: :get,
    url: test_url,
    timeout: 60
  )

  puts "響應狀態碼: #{response.code}"
  puts "Content-Type: #{response.headers[:content_type] || response.headers['content-type']}"
  puts "Content-Length: #{response.headers[:content_length] || response.headers['content-length']}"
  puts "檔案大小: #{response.body.bytesize} bytes"
  puts

  # 2. 檢查文件頭
  puts '2. 檢查文件頭...'
  header = response.body[0, 20]
  puts "文件頭 (hex): #{header.unpack1('H*')}"

  # 檢查 JPEG 文件頭
  if header.start_with?("\xFF\xD8\xFF".force_encoding('BINARY'))
    puts '✓ 檢測到 JPEG 文件頭'
  else
    puts '✗ 未檢測到有效的 JPEG 文件頭'
  end
  puts

  # 3. 保存為臨時文件測試
  puts '3. 保存為臨時文件...'
  temp_file = Tempfile.new(['test_download', '.jpg'])
  temp_file.binmode
  temp_file.write(response.body)
  temp_file.rewind

  puts "臨時文件路徑: #{temp_file.path}"
  puts "臨時文件大小: #{temp_file.size} bytes"
  puts

  # 4. 測試 DifyFileUploadService
  puts '4. 測試 DifyFileUploadService...'

  # 假設我們有一個 app_key 和 user_id（您需要根據實際情況調整）
  app_key = ENV['DIFY_IELTS_TASK_1_APP_KEY'] || 'your_test_app_key'
  user_id = 'test_user_123'

  puts "使用 app_key: #{app_key[0, 10]}..."
  puts "使用 user_id: #{user_id}"
  puts

  upload_service = DifyFileUploadService.new(app_key, user_id)

  # 測試從 URL 上傳
  puts '4a. 測試從 URL 上傳...'
  upload_result = upload_service.upload_from_url(test_url, 'image')

  if upload_result.success?
    puts '✓ 文件上傳成功!'
    puts "Upload file ID: #{upload_result.upload_file_id}"
  else
    puts "✗ 文件上傳失敗: #{upload_result.error_message}"
  end
  puts

  # 5. 測試直接文件上傳
  puts '5. 測試直接文件上傳...'
  direct_upload_result = upload_service.upload_file(temp_file, 'image')

  if direct_upload_result.success?
    puts '✓ 直接文件上傳成功!'
    puts "Upload file ID: #{direct_upload_result.upload_file_id}"
  else
    puts "✗ 直接文件上傳失敗: #{direct_upload_result.error_message}"
  end

  # 清理
  temp_file.close
  temp_file.unlink
rescue StandardError => e
  puts "錯誤: #{e.message}"
  puts "錯誤類型: #{e.class}"
  puts '錯誤堆棧:'
  puts e.backtrace.first(10).join("\n")
end

puts "\n=== 測試完成 ==="
