# frozen_string_literal: true

namespace :aienglish do
  desc '根據用戶郵箱後綴設置學校歸屬，並建立相應的學年和註冊記錄'
  task setup_schools_by_email: :environment do
    # 定義學校映射關係
    SCHOOL_MAPPINGS = {
      # 學校 A 的郵箱規則
      'schoola.edu.hk' => {
        name: '學校 A',
        code: 'SCHOOL_A',
        academic_year: {
          name: '2023-2024',
          start_date: Date.new(2023, 9, 1),
          end_date: Date.new(2024, 8, 31)
        }
      },
      # 學校 B 的郵箱規則
      'schoolb.edu.hk' => {
        name: '學校 B',
        code: 'SCHOOL_B',
        academic_year: {
          name: '2023-2024',
          start_date: Date.new(2023, 9, 1),
          end_date: Date.new(2024, 8, 31)
        }
      }
      # 可以繼續添加更多學校
    }.freeze

    # 創建或更新學校和學年的方法
    def setup_school_and_academic_year(school_info)
      # 查找或創建學校
      school = School.find_or_create_by(code: school_info[:code]) do |s|
        s.name = school_info[:name]
        s.status = :active
        s.timezone = 'Asia/Hong_Kong'
      end

      # 查找或創建學年
      academic_year = SchoolAcademicYear.find_or_create_by(
        school:,
        name: school_info[:academic_year][:name]
      ) do |ay|
        ay.start_date = school_info[:academic_year][:start_date]
        ay.end_date = school_info[:academic_year][:end_date]
        ay.status = :active
      end

      [school, academic_year]
    end

    # 處理用戶數據
    def process_user(user, school, academic_year)
      # 更新用戶所屬學校
      user.update!(school:) unless user.school == school

      # 創建或更新學生註冊記錄
      enrollment = StudentEnrollment.find_or_create_by(
        general_user: user,
        school_academic_year: academic_year
      ) do |e|
        e.class_name = user.banbie
        e.class_number = user.class_no
        e.status = :active
      end

      # 更新該用戶的所有 EssayGrading 記錄
      user.essay_gradings.find_each do |grading|
        grading.update!(
          submission_class_name: enrollment.class_name,
          submission_class_number: enrollment.class_number,
          submission_school_id: school.id,
          submission_academic_year_id: academic_year.id
        )
      end
    end

    # 主要處理邏輯
    begin
      # 1. 按郵箱後綴分組處理用戶
      SCHOOL_MAPPINGS.each do |email_domain, school_info|
        puts "Processing users from domain: #{email_domain}"

        # 獲取該域名下的所有用戶
        users = GeneralUser.where('email LIKE ?', "%@#{email_domain}")

        if users.exists?
          # 設置學校和學年
          school, academic_year = setup_school_and_academic_year(school_info)

          # 批次處理用戶
          users.find_each(batch_size: 100) do |user|
            process_user(user, school, academic_year)
            print '.' # 進度指示
          rescue StandardError => e
            puts "\nError processing user #{user.id}: #{e.message}"
          end

          puts "\nProcessed #{users.count} users for #{school.name}"
        else
          puts "No users found for domain: #{email_domain}"
        end
      end

      # 2. 處理未匹配的用戶（可選）
      unmatched_users = GeneralUser.where.not(
        email: SCHOOL_MAPPINGS.keys.map { |domain| "%@#{domain}" }
      )

      if unmatched_users.exists?
        puts "\nProcessing unmatched users..."

        # 創建默認學校
        default_school_info = {
          name: '其他學校',
          code: 'DEFAULT',
          academic_year: {
            name: '2023-2024',
            start_date: Date.new(2023, 9, 1),
            end_date: Date.new(2024, 8, 31)
          }
        }

        default_school, default_academic_year = setup_school_and_academic_year(default_school_info)

        unmatched_users.find_each(batch_size: 100) do |user|
          process_user(user, default_school, default_academic_year)
          print '.'
        rescue StandardError => e
          puts "\nError processing unmatched user #{user.id}: #{e.message}"
        end

        puts "\nProcessed #{unmatched_users.count} unmatched users"
      end
    rescue StandardError => e
      puts "Error during processing: #{e.message}"
      puts e.backtrace
    end
  end

  # 添加一個任務來顯示當前的處理狀態
  desc '顯示學校設置的統計信息'
  task show_statistics: :environment do
    puts "\n=== 學校統計 ==="
    School.all.each do |school|
      puts "\n學校: #{school.name} (#{school.code})"
      puts "用戶數量: #{school.general_users.count}"
      puts "學年數量: #{school.school_academic_years.count}"
      puts "學生註冊記錄: #{school.student_enrollments.count}"
      puts '----------------------------------------'
    end
  end
end
