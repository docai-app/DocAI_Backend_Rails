#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../config/environment'

puts '=== 檢查 IELTS Task 1 數據 ==='

# 查找 IELTS Task 1 作業
ielts_assignments = EssayAssignment.where("rubric->>'name' = ?", 'IELTS Task 1')
puts "找到 #{ielts_assignments.count} 個 IELTS Task 1 作業"

ielts_assignments.each do |assignment|
  puts "\n作業 ID: #{assignment.id}"
  puts "  標題: #{assignment.title}"
  puts "  有圖片: #{assignment.graph_image.attached?}"

  # 查找相關的 essay gradings
  gradings = assignment.essay_gradings.limit(3)
  puts "  相關 Essay Gradings: #{gradings.count}"

  gradings.each do |grading|
    puts "    - Grading ID: #{grading.id}, Status: #{grading.status}"
  end
end

puts "\n=== 完成 ==="
