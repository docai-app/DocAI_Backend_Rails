#!/usr/bin/env ruby

# 監控 IELTS Task 1 功能的腳本
# 執行: rails runner scripts/monitor_ielts_test.rb

puts '🔍 IELTS Task 1 功能監控'
puts '=' * 40

# 查找最近的 IELTS Task 1 作業
puts "\n📋 查找 IELTS Task 1 作業..."

ielts_assignments = EssayAssignment.joins(:rubric)
                                   .where("rubric->>'name' = ?", 'IELTS Task 1')
                                   .order(created_at: :desc)
                                   .limit(5)

if ielts_assignments.empty?
  puts '❌ 沒有找到 IELTS Task 1 作業'
  puts '請先創建一個 IELTS Task 1 作業進行測試'
  exit
end

puts "✅ 找到 #{ielts_assignments.count} 個 IELTS Task 1 作業"

ielts_assignments.each do |assignment|
  puts "\n📄 作業 ID: #{assignment.id}"
  puts "   標題: #{assignment.title}"
  puts "   主題: #{assignment.topic}"
  puts "   有圖片: #{assignment.graph_image.attached? ? '✅' : '❌'}"
  puts "   創建時間: #{assignment.created_at}"

  # 檢查該作業的批改記錄
  gradings = assignment.essay_gradings.order(created_at: :desc).limit(3)

  if gradings.any?
    puts "   📊 批改記錄: #{gradings.count} 份"

    gradings.each do |grading|
      puts "     └─ ID: #{grading.id}, 狀態: #{grading.status}, 創建時間: #{grading.created_at}"

      # 測試我們的檢測邏輯
      puts "     └─ IELTS 檢測: #{grading.essay_assignment.rubric&.dig('name') == 'IELTS Task 1' ? '✅ 正確' : '❌ 失敗'}"
    end
  else
    puts '   📊 批改記錄: 無'
  end
end

# 測試服務類的檢測邏輯
puts "\n🧪 測試檢測邏輯..."

latest_assignment = ielts_assignments.first
if latest_assignment.essay_gradings.any?
  test_grading = latest_assignment.essay_gradings.first

  # 模擬 EssayGradingService 的邏輯
  def is_ielts_task_1?(essay_grading)
    essay_grading.essay_assignment.rubric&.dig('name') == 'IELTS Task 1'
  end

  result = is_ielts_task_1?(test_grading)
  puts "✅ 檢測結果: #{result ? 'IELTS Task 1' : '標準作業'}"

  if result && latest_assignment.graph_image.attached?
    puts "✅ 圖片 URL: #{latest_assignment.graph_image.url[0..60]}..."
  elsif result
    puts '⚠️  警告: IELTS Task 1 作業缺少圖片'
  end
else
  puts '⚠️  沒有批改記錄可供測試'
end

# 提供測試建議
puts "\n💡 測試建議:"
puts '1. 如果沒有 IELTS Task 1 作業，請先創建一個'
puts '2. 提交一份作文觸發批改流程'
puts '3. 查看日誌確認是否使用了新的參數格式'
puts "4. 監控命令: tail -f log/development.log | grep 'IELTS\\|EssayGradingService'"

puts "\n📊 系統狀態檢查完成"
