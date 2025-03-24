# frozen_string_literal: true

namespace :essay_grading do
  desc 'Backfill submission info for existing essay gradings'
  task backfill_submission_info: :environment do
    puts '開始處理 essay_grading 的 submission 信息...'

    total_count = EssayGrading.count
    processed_count = 0
    updated_count = 0
    error_count = 0

    begin
      EssayGrading.find_each do |grading|
        processed_count += 1

        # 跳過已經有 submission 信息的記錄
        next if grading.submission_class_name.present? && grading.submission_class_number.present?

        # 獲取用戶信息
        user = grading.general_user
        unless user
          puts "警告: essay_grading #{grading.id} 沒有關聯的用戶"
          error_count += 1
          next
        end

        # 使用備用信息填充
        grading.update_columns(
          submission_class_name: user.banbie,
          submission_class_number: user.class_no
        )

        # 如果有入學記錄，補充學校和學年信息
        if ((enrollment = user.current_enrollment)) && (school_academic_year = enrollment.school_academic_year)
          grading.update_columns(
            submission_school_id: school_academic_year.school_id,
            submission_academic_year_id: school_academic_year.id
          )
        end

        updated_count += 1

        # 每處理 1000 條記錄輸出一次進度
        puts "已處理 #{processed_count}/#{total_count} 條記錄，更新了 #{updated_count} 條" if (processed_count % 1000).zero?
      end

      puts "\n處理完成！"
      puts "總記錄數: #{total_count}"
      puts "處理記錄數: #{processed_count}"
      puts "更新記錄數: #{updated_count}"
      puts "錯誤記錄數: #{error_count}"
    rescue StandardError => e
      puts "處理過程中發生錯誤: #{e.message}"
      puts e.backtrace
      raise e
    end
  end
end
