#!/usr/bin/env ruby
# frozen_string_literal: true

# 簡化測試：測試 Active Storage 的 Azure 圖片處理
require_relative '../config/environment'

puts '=== 測試 Active Storage Azure 圖片處理 ==='

begin
  # 1. 查找有 graph_image 的 IELTS Task 1 作業
  puts '1. 查找 IELTS Task 1 作業...'

  ielts_assignments = EssayAssignment.where("rubric->>'name' = ?", 'IELTS Task 1')
  puts "找到 #{ielts_assignments.count} 個 IELTS Task 1 作業"

  assignments_with_image = ielts_assignments.select { |a| a.graph_image.attached? }
  puts "其中 #{assignments_with_image.count} 個有圖片"

  if assignments_with_image.empty?
    puts '⚠️ 沒有找到帶圖片的 IELTS Task 1 作業'
    puts '可用的作業類型:'
    EssayAssignment.all.each do |a|
      puts "  - ID: #{a.id}, Category: #{a.category}, Rubric Name: #{a.rubric&.dig('name')}, Has Image: #{a.graph_image.attached?}"
    end
    exit
  end

  # 2. 測試第一個帶圖片的作業
  assignment = assignments_with_image.first
  puts "\n2. 測試作業 ID: #{assignment.id}"
  puts "   標題: #{assignment.title}"
  puts "   類別: #{assignment.category}"
  puts "   Rubric Name: #{assignment.rubric&.dig('name')}"

  # 3. 測試 graph_image.url
  puts "\n3. 測試 graph_image.url..."

  begin
    graph_url = assignment.graph_image.url
    puts "✓ 圖片 URL: #{graph_url}"

    # 4. 測試下載圖片
    puts "\n4. 測試下載圖片..."

    response = RestClient::Request.execute(
      method: :get,
      url: graph_url,
      timeout: 30
    )

    puts '✓ 下載成功!'
    puts "  狀態碼: #{response.code}"
    puts "  Content-Type: #{response.headers[:content_type] || response.headers['content-type']}"
    puts "  檔案大小: #{response.body.bytesize} bytes"

    # 5. 檢查文件頭
    header = response.body[0, 20]
    puts "  文件頭 (hex): #{header.unpack1('H*')[0, 20]}..."

    # 檢查 JPEG 文件頭，避免修改凍結字符串
    jpeg_signature = "\xFF\xD8\xFF".b
    if header[0, 3] == jpeg_signature
      puts '  ✓ 檢測到 JPEG 文件頭'
    else
      puts '  ⚠️ 未檢測到標準 JPEG 文件頭'
    end

    # 6. 測試 DifyFileUploadService
    puts "\n6. 測試 DifyFileUploadService..."

    app_key = ENV['DIFY_IELTS_TASK_1_APP_KEY']
    if app_key
      user_id = assignment.general_user_id || 'test_user'

      puts "  使用 app_key: #{app_key[0, 10]}..."
      puts "  使用 user_id: #{user_id}"

      upload_service = DifyFileUploadService.new(app_key, user_id)
      upload_result = upload_service.upload_from_url(graph_url, 'image')

      if upload_result.success?
        puts '  ✓ 文件上傳成功!'
        puts "  Upload file ID: #{upload_result.upload_file_id}"
      else
        puts "  ✗ 文件上傳失敗: #{upload_result.error_message}"
      end
    else
      puts '⚠️ 環境變量 DIFY_IELTS_TASK_1_APP_KEY 未設置，跳過 Dify 上傳測試'
    end
  rescue RestClient::ExceptionWithResponse => e
    puts "✗ 下載失敗: #{e.message}"
    puts "  狀態碼: #{e.response&.code}"
    puts "  響應: #{e.response&.body}"
  rescue StandardError => e
    puts "✗ 獲取 URL 失敗: #{e.message}"
    puts "  錯誤類型: #{e.class}"
  end
rescue StandardError => e
  puts "錯誤: #{e.message}"
  puts "錯誤類型: #{e.class}"
  puts '錯誤堆棧:'
  puts e.backtrace.first(10).join("\n")
end

puts "\n=== 測試完成 ==="
