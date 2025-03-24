# frozen_string_literal: true

namespace :aienglish do
  # 添加一個任務來顯示當前的處理狀態
  desc '顯示學校設置的統計信息'
  task show_statistics: :environment do
    puts "\n=== 學校統計 ==="
    School.all.each do |school|
      puts "\n學校: #{school.name} (#{school.code})"
      puts "用戶數量: #{school.student_enrollments.count + school.teacher_assignments.count}"
      puts "學年數量: #{school.school_academic_years.count}"
      puts "學生註冊記錄: #{school.student_enrollments.count}"
      puts "教師註冊記錄: #{school.teacher_assignments.count}"
      puts '----------------------------------------'
    end
  end
end
