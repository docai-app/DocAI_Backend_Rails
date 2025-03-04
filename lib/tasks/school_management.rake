# frozen_string_literal: true

# lib/tasks/school_management.rake

# 學校管理系統 Rake 任務使用說明
# ============================
#
# 教師管理
# --------
# 1. 分配單個教師:
#    $ rails school:assign_teachers[學校代碼,學年,"@郵箱域名",部門,職位]
#    例如: $ rails school:assign_teachers[SCHOOL_A,2023-2024,"@schoola.edu.hk","英文部","教師"]
#
# 2. 批量分配多個教師:
#    $ rails school:assign_teachers[學校代碼,學年,"@域名1;@域名2",部門,職位]
#    例如: $ rails school:assign_teachers[SCHOOL_A,2023-2024,"@schoola.edu.hk;@schoolb.edu.hk","英文部","教師"]
#
# 3. 查看教師統計:
#    $ rails school:show_teacher_stats[學校代碼]
#    例如: $ rails school:show_teacher_stats[SCHOOL_A]
#
# 學生管理
# --------
# 1. 分配學生:
#    $ rails school:assign_students[學校代碼,學年,"@郵箱域名"]
#    例如: $ rails school:assign_students[SCHOOL_A,2023-2024,"@schoola.edu.hk"]
#
# 2. 批量分配學生:
#    $ rails school:assign_students[學校代碼,學年,"@域名1;@域名2"]
#    例如: $ rails school:assign_students[SCHOOL_A,2023-2024,"@schoola.edu.hk;@schoolb.edu.hk"]
#
# 3. 查看學生統計:
#    $ rails school:show_student_stats[學校代碼]
#    例如: $ rails school:show_student_stats[SCHOOL_A]
#
# 學校管理
# --------
# 1. 創建新學校（互動模式）:
#    $ rails school:create[input]
#
# 2. 從 CSV 文件創建學校:
#    $ rails school:create[csv] CSV_FILE=檔案路徑
#    例如: $ rails school:create[csv] CSV_FILE=temp/schools.csv
#
# 3. 查看學校列表:
#    $ rails school:list
#
# CSV 文件格式
# -----------
# schools.csv 文件格式示例：
# name,code,status,address,contact_email,contact_phone,region,timezone,school_type,curriculum_type,academic_system,academic_years
# 澳門測試學校,SCHOOL_MO,active,澳門XX區XX街XX號,contact@school.mo,+853-12345678,mo,Asia/Macau,secondary,local,6_3_3,"2023-2024:active;2024-2025:preparing"
#
# 注意事項
# --------
# 1. 所有命令都支持香港和澳門地區的學校
# 2. 教師和學生分配時會自動檢查 AI English 用戶身份
# 3. 學年信息可以通過 CSV 導入或在創建學校時手動設置
# 4. 統計功能提供詳細的用戶分佈信息
# 5. 所有操作都在事務中執行，確保數據一致性
#
# 常見問題處理
# -----------
# 1. 如果遇到權限問題，請確保已登入並有相應權限
# 2. CSV 導入失敗時，請檢查文件格式是否正確
# 3. 分配用戶時如果找不到對應學校或學年，請先確認學校和學年是否存在
# 4. 統計數據不準確時，可以嘗試重新運行相應的分配命令
#
# 建議使用順序
# -----------
# 1. 先創建學校（create）
# 2. 確認學校信息（list）
# 3. 分配教師（assign_teachers）
# 4. 分配學生（assign_students）
# 5. 查看統計信息（show_teacher_stats/show_student_stats）

require 'csv'

namespace :school do
  # 定義共用的常量
  module SchoolConstants
    REGIONS = {
      'hk' => '香港',
      'mo' => '澳門'
    }.freeze

    SCHOOL_TYPES = {
      'hk' => {
        'primary' => '小學',
        'secondary' => '中學',
        'kindergarten' => '幼稚園',
        'international' => '國際學校',
        'college' => '大專院校'
      },
      'mo' => {
        'primary' => '小學',
        'secondary' => '中學',
        'kindergarten' => '幼稚園',
        'international' => '國際學校',
        'vocational' => '職業技術學校',
        'college' => '大專院校'
      }
    }.freeze

    CURRICULUM_TYPES = {
      'hk' => {
        'local' => '本地課程',
        'ib' => 'IB課程',
        'ap' => 'AP課程',
        'igcse' => 'IGCSE課程',
        'custom' => '自定義課程'
      },
      'mo' => {
        'local' => '本地課程',
        'ib' => 'IB課程',
        'ap' => 'AP課程',
        'portuguese' => '葡文課程',
        'chinese' => '中文課程',
        'custom' => '自定義課程'
      }
    }.freeze

    ACADEMIC_SYSTEMS = {
      'hk' => {
        '6_3_3' => '6+3+3制',
        '6_6' => '6+6制',
        'custom' => '自定義學制'
      },
      'mo' => {
        '6_3_3' => '6+3+3制',
        '6_6' => '6+6制',
        '15_years' => '十五年一貫制',
        'custom' => '自定義學制'
      }
    }.freeze

    TIMEZONE_BY_REGION = {
      'hk' => 'Asia/Hong_Kong',
      'mo' => 'Asia/Macau'
    }.freeze

    ACADEMIC_YEAR_DEFAULTS = {
      'mo' => {
        start_month: 9,
        end_month: 8
      },
      'hk' => {
        start_month: 9,
        end_month: 8
      }
    }.freeze
  end

  desc '創建或更新學校信息，支援香港和澳門地區的學校系統'
  task :create, [:mode] => :environment do |_task, args|
    class SchoolCreator
      include SchoolConstants

      # 定義課程類型（按地區）
      CURRICULUM_TYPES = {
        'hk' => {
          'local' => '本地課程',
          'ib' => 'IB課程',
          'ap' => 'AP課程',
          'igcse' => 'IGCSE課程',
          'custom' => '自定義課程'
        },
        'mo' => {
          'local' => '本地課程',
          'ib' => 'IB課程',
          'ap' => 'AP課程',
          'portuguese' => '葡文課程',
          'chinese' => '中文課程',
          'custom' => '自定義課程'
        }
      }.freeze

      # 定義學制（按地區）
      ACADEMIC_SYSTEMS = {
        'hk' => {
          '6_3_3' => '6+3+3制',
          '6_6' => '6+6制',
          'custom' => '自定義學制'
        },
        'mo' => {
          '6_3_3' => '6+3+3制',
          '6_6' => '6+6制',
          '15_years' => '十五年一貫制',
          'custom' => '自定義學制'
        }
      }.freeze

      # 定義默認時區
      TIMEZONE_BY_REGION = {
        'hk' => 'Asia/Hong_Kong',
        'mo' => 'Asia/Macau'
      }.freeze

      # 定義學年的默認設置
      ACADEMIC_YEAR_DEFAULTS = {
        'mo' => {
          start_month: 9,
          end_month: 8
        },
        'hk' => {
          start_month: 9,
          end_month: 8
        }
      }.freeze

      def self.create_from_input
        puts "\n=== 開始創建新學校 ==="
        @region = prompt_with_options('選擇地區', REGIONS.keys)
        school_data = gather_school_info
        create_school(school_data)
      end

      def self.create_from_csv(file_path)
        puts "\n=== 從 CSV 文件創建學校 ==="

        unless File.exist?(file_path)
          puts "錯誤: 找不到 CSV 文件 #{file_path}"
          return
        end

        CSV.foreach(file_path, headers: true) do |row|
          data = row.to_h
          @region = data['region']&.downcase
          unless REGIONS.key?(@region)
            puts "警告: 無效的地區 '#{@region}' (學校: #{data['name']})"
            next
          end
          create_school(data)
        rescue StandardError => e
          puts "處理行時發生錯誤: #{e.message}"
          puts "行內容: #{row.inspect}"
        end
      end

      def self.gather_school_info
        {
          'name' => prompt('學校名稱'),
          'code' => prompt('學校代碼 (唯一標識)'),
          'status' => prompt_with_options('學校狀態', School.statuses.keys),
          'address' => prompt('學校地址'),
          'contact_email' => prompt('聯繫郵箱'),
          'contact_phone' => prompt('聯繫電話'),
          'region' => @region,
          'timezone' => prompt_with_default('時區', TIMEZONE_BY_REGION[@region]),
          'school_type' => prompt_with_options('學校類型', SCHOOL_TYPES[@region].keys),
          'curriculum_type' => prompt_with_options('課程類型', CURRICULUM_TYPES[@region].keys),
          'academic_system' => prompt_with_options('學制', ACADEMIC_SYSTEMS[@region].keys),
          'custom_settings' => gather_custom_settings
        }
      end

      def self.create_school(data)
        # 在一個事務中處理學校和學年的創建
        ActiveRecord::Base.transaction do
          # 準備學校的基本數據
          school_attributes = {
            name: data['name'],
            code: data['code'],
            status: data['status'] || 'active',
            address: data['address'],
            contact_email: data['contact_email'],
            contact_phone: data['contact_phone'],
            timezone: data['timezone'],
            meta: {
              region: data['region'],
              school_type: data['school_type'],
              curriculum_type: data['curriculum_type'],
              academic_system: data['academic_system'],
              custom_settings: data['custom_settings'] || {}
            }
          }

          # 創建或更新學校
          school = School.find_or_initialize_by(code: school_attributes[:code])

          action = if school.new_record?
                     '創建'
                   else
                     '更新'
                   end

          if school.update(school_attributes)
            # 處理學年信息
            create_academic_years(school, data)
            puts "成功#{action}學校: #{school.name} (#{school.code})"
          else
            puts "#{action}學校失敗: #{school.errors.full_messages.join(', ')}"
            raise ActiveRecord::Rollback
          end
        end
      end

      def self.create_academic_years(school, data)
        # 解析學年數據（如果提供）
        academic_years = parse_academic_years(data)

        academic_years.each do |year_data|
          create_single_academic_year(school, year_data)
        end
      end

      def self.parse_academic_years(data)
        # 如果提供了學年數據，則解析它
        if data['academic_years'].present?
          begin
            # 嘗試解析 JSON 格式的學年數據
            JSON.parse(data['academic_years'])
          rescue JSON::ParserError
            # 如果不是 JSON 格式，假設是用分號分隔的字符串
            parse_academic_years_string(data['academic_years'])
          end
        else
          # 如果沒有提供學年數據，創建一個默認的當前學年
          [generate_default_academic_year(data['region'])]
        end
      end

      def self.parse_academic_years_string(years_string)
        # 解析格式如 "2023-2024:active;2024-2025:preparing" 的字符串
        years_string.split(';').map do |year_str|
          name, status = year_str.split(':')
          start_year = name.split('-').first.to_i

          {
            'name' => name,
            'status' => status || 'active',
            'start_year' => start_year
          }
        end
      end

      def self.generate_default_academic_year(region)
        current_year = Date.today.year
        defaults = ACADEMIC_YEAR_DEFAULTS[region] || ACADEMIC_YEAR_DEFAULTS['hk']

        {
          'name' => "#{current_year}-#{current_year + 1}",
          'status' => 'active',
          'start_year' => current_year,
          'start_month' => defaults[:start_month],
          'end_month' => defaults[:end_month]
        }
      end

      def self.create_single_academic_year(school, year_data)
        # 設置學年的起始和結束日期
        start_year = year_data['start_year']
        start_month = year_data['start_month'] || ACADEMIC_YEAR_DEFAULTS[school.meta['region']][:start_month]
        end_month = year_data['end_month'] || ACADEMIC_YEAR_DEFAULTS[school.meta['region']][:end_month]

        start_date = Date.new(start_year, start_month, 1)
        end_date = if end_month < start_month
                     Date.new(start_year + 1, end_month, -1) # 使用 -1 來獲取月份的最後一天
                   else
                     Date.new(start_year, end_month, -1)
                   end

        # 創建或更新學年
        academic_year = school.school_academic_years.find_or_initialize_by(name: year_data['name'])
        academic_year.update!(
          start_date:,
          end_date:,
          status: year_data['status']
        )
      rescue StandardError => e
        puts "創建學年失敗 (#{year_data['name']}): #{e.message}"
        raise
      end

      # 輔助方法
      def self.prompt(message)
        print "#{message}: "
        $stdin.gets.chomp
      end

      def self.prompt_with_options(message, options)
        puts "\n#{message}:"
        options.each_with_index do |option, index|
          puts "#{index + 1}. #{option}"
        end
        print "請選擇 (1-#{options.length}): "

        choice = $stdin.gets.chomp.to_i
        return options[choice - 1] if choice.between?(1, options.length)

        options.first # 返回默認選項
      end

      def self.prompt_with_default(message, default)
        print "#{message} [#{default}]: "
        input = $stdin.gets.chomp
        input.empty? ? default : input
      end

      def self.gather_custom_settings
        custom_settings = {}

        puts "\n是否添加自定義設置？(y/n)"
        return custom_settings unless $stdin.gets.chomp.downcase == 'y'

        loop do
          key = prompt('設置鍵名 (留空結束)')
          break if key.empty?

          value = prompt('設置值')
          custom_settings[key] = value
        end

        custom_settings
      end
    end

    # 主要執行邏輯
    begin
      mode = args[:mode] || 'input'

      case mode
      when 'csv'
        file_path = ENV['CSV_FILE'] || 'schools.csv'
        SchoolCreator.create_from_csv(file_path)
      when 'input'
        SchoolCreator.create_from_input
      else
        puts "無效的模式。請使用 'csv' 或 'input'"
      end
    rescue StandardError => e
      puts "執行過程中發生錯誤: #{e.message}"
      puts e.backtrace
    end
  end

  # 修改列表顯示任務
  desc '顯示所有學校的詳細信息'
  task list: :environment do
    include SchoolConstants

    puts "\n=== 學校列表 ==="
    School.all.each do |school|
      region = school.meta['region']

      puts "\n學校信息:"
      puts '--------------------------------'
      puts "名稱: #{school.name}"
      puts "代碼: #{school.code}"
      puts "地區: #{REGIONS[region] || '未指定'}"
      puts "狀態: #{school.status}"
      puts "地址: #{school.address}"
      puts "聯繫郵箱: #{school.contact_email}"
      puts "聯繫電話: #{school.contact_phone}"
      puts "時區: #{school.timezone}"

      # 安全地獲取元數據
      meta = school.meta || {}
      puts "\n元數據:"
      puts "學校類型: #{meta['school_type']}"
      puts "課程類型: #{meta['curriculum_type']}"
      puts "學制: #{meta['academic_system']}"

      puts "\n學年信息:"
      school.school_academic_years.each do |year|
        puts "- #{year.name} (#{year.status})"
      end
      puts '--------------------------------'
    end
  end

  desc '將特定郵箱後綴的 AI English 學生加入指定學校和學年'
  task :assign_students, %i[school_code academic_year_name email_patterns] => :environment do |_task, args|
    class StudentAssigner
      def self.assign_students(school_code:, academic_year_name:, email_patterns:)
        # 驗證參數
        unless school_code.present? && academic_year_name.present? && email_patterns.present?
          puts '錯誤: 缺少必要參數'
          puts '使用方式: rails school:assign_students[school_code,academic_year_name,"pattern1;pattern2"]'
          puts '例如: rails school:assign_students[SCHOOL_A,2023-2024,"@schoola.edu.hk;@schoolb.edu.hk"]'
          return
        end

        # 查找學校
        school = School.find_by(code: school_code)
        unless school
          puts "錯誤: 找不到學校代碼 #{school_code}"
          return
        end

        # 查找學年
        academic_year = school.school_academic_years.find_by(name: academic_year_name)
        unless academic_year
          puts "錯誤: 在學校 #{school.name} 中找不到學年 #{academic_year_name}"
          return
        end

        # 解析郵箱模式
        patterns = email_patterns.split(';').map(&:strip)

        # 開始處理
        puts "\n=== 開始分配 AI English 學生 ==="
        puts "學校: #{school.name}"
        puts "學年: #{academic_year.name}"
        puts "郵箱模式: #{patterns.join(', ')}"

        # 使用事務來確保數據一致性
        ActiveRecord::Base.transaction do
          patterns.each do |pattern|
            process_pattern(pattern, school, academic_year)
          end
        end
      end

      def self.process_pattern(pattern, school, academic_year)
        # 只查找 AI English 用戶
        users = GeneralUser.where('email LIKE ?', "%#{pattern}")
                           .select(&:aienglish_user?)

        if users.empty?
          puts "\n沒有找到符合模式 #{pattern} 的 AI English 用戶"
          return
        end

        puts "\n處理郵箱模式: #{pattern}"
        puts "找到 #{users.count} 個 AI English 用戶"

        # 批量處理用戶
        users.each do |user|
          assign_single_user(user, school, academic_year)
          print '.' # 進度指示
        end
        puts # 換行
      end

      def self.assign_single_user(user, school, academic_year)
        # 檢查用戶角色
        unless user.aienglish_user?
          puts "\n跳過非 AI English 用戶: #{user.email}"
          return
        end

        # 檢查用戶是否為教師
        is_teacher = user.meta['aienglish_role'] == 'teacher'
        if is_teacher
          puts "\n跳過教師用戶: #{user.email}"
          return # 教師不需要創建學生註冊記錄
        end

        # 創建或更新學生註冊記錄
        enrollment = StudentEnrollment.find_or_initialize_by(
          general_user: user,
          school_academic_year: academic_year
        )

        # 如果是新記錄，設置班級信息
        if enrollment.new_record?
          enrollment.class_name = user.banbie.presence || '未分配'
          enrollment.class_number = user.class_no.presence || '未分配'
          enrollment.status = :active
          enrollment.save!
        end

        # 更新該用戶的所有未完成的 EssayGrading 記錄
        update_essay_gradings(user, school, academic_year, enrollment)
      rescue StandardError => e
        puts "\n處理用戶 #{user.email} 時發生錯誤: #{e.message}"
        raise # 重新拋出異常以觸發事務回滾
      end

      def self.update_essay_gradings(user, school, academic_year, enrollment)
        # 只更新最近30天的作業記錄
        recent_date = 30.days.ago
        user.essay_gradings
            .where('created_at > ?', recent_date)
            .find_each do |grading|
          grading.update!(
            submission_class_name: enrollment.class_name,
            submission_class_number: enrollment.class_number,
            submission_school_id: school.id,
            submission_academic_year_id: academic_year.id
          )
        end
      end
    end

    # 執行分配任務
    begin
      StudentAssigner.assign_students(
        school_code: args[:school_code],
        academic_year_name: args[:academic_year_name],
        email_patterns: args[:email_patterns]
      )
    rescue StandardError => e
      puts "\n執行過程中發生錯誤:"
      puts e.message
      puts e.backtrace
    end
  end

  # 修改統計任務以顯示 AI English 用戶信息
  desc '顯示學校學生分配統計'
  task :show_student_stats, [:school_code] => :environment do |_task, args|
    school = School.find_by(code: args[:school_code])

    unless school
      puts "錯誤: 找不到學校代碼 #{args[:school_code]}"
      next
    end

    puts "\n=== #{school.name} AI English 用戶統計 ==="

    # 顯示學生統計（按學年和班級）
    puts "\n學生統計:"
    school.school_academic_years.order(start_date: :desc).each do |year|
      puts "\n學年: #{year.name}"

      # 只獲取學生用戶的註冊記錄
      enrollments = year.student_enrollments.includes(:general_user)
                        .select { |e| e.general_user.aienglish_user? && e.general_user.meta['aienglish_role'] != 'teacher' }

      # 按班級分組統計
      enrollments.group_by(&:class_name).each do |class_name, class_enrollments|
        puts "  班級: #{class_name || '未分配'}"
        puts "  學生人數: #{class_enrollments.count}"
        puts '  郵箱域名統計:'

        # 統計郵箱域名分佈
        email_domains = class_enrollments.map { |e| e.general_user.email.split('@').last }
        email_domains.tally.each do |domain, count|
          puts "    - @#{domain}: #{count}人"
        end
        puts
      end
    end
  end

  # 添加新的任務用於分配教師
  desc '將特定郵箱後綴的 AI English 教師分配到指定學校和學年'
  task :assign_teachers,
       %i[school_code academic_year_name email_patterns department position] => :environment do |_task, args|
    class TeacherAssigner
      def self.assign_teachers(school_code:, academic_year_name:, email_patterns:, department:, position:)
        # 驗證參數
        unless school_code.present? && academic_year_name.present? && email_patterns.present?
          puts '錯誤: 缺少必要參數'
          puts '使用方式: rails school:assign_teachers[school_code,academic_year_name,"pattern1;pattern2",department,position]'
          puts '例如: rails school:assign_teachers[SCHOOL_A,2023-2024,"@schoola.edu.hk","英文部","教師"]'
          return
        end

        # 查找學校和學年
        school = School.find_by(code: school_code)
        academic_year = school&.school_academic_years&.find_by(name: academic_year_name)

        unless school && academic_year
          puts '錯誤: 找不到指定的學校或學年'
          return
        end

        # 解析郵箱模式
        patterns = email_patterns.split(';').map(&:strip)

        # 開始處理
        puts "\n=== 開始分配 AI English 教師 ==="
        puts "學校: #{school.name}"
        puts "學年: #{academic_year.name}"
        puts "部門: #{department}"
        puts "職位: #{position}"
        puts "郵箱模式: #{patterns.join(', ')}"

        ActiveRecord::Base.transaction do
          patterns.each do |pattern|
            process_pattern(pattern, school, academic_year, department, position)
          end
        end
      end

      def self.process_pattern(pattern, school, academic_year, department, position)
        # 只查找 AI English 教師
        teachers = GeneralUser.where('email LIKE ?', "%#{pattern}")
                              .select { |user| user.aienglish_user? && user.meta['aienglish_role'] == 'teacher' }

        if teachers.empty?
          puts "\n沒有找到符合模式 #{pattern} 的 AI English 教師"
          return
        end

        puts "\n處理郵箱模式: #{pattern}"
        puts "找到 #{teachers.count} 個 AI English 教師"

        teachers.each do |teacher|
          assign_single_teacher(teacher, school, academic_year, department, position)
          print '.'
        end
        puts
      end

      def self.assign_single_teacher(teacher, school, academic_year, department, position)
        # 創建或更新教師任教記錄
        assignment = TeacherAssignment.find_or_initialize_by(
          general_user: teacher,
          school_academic_year: academic_year
        )

        if assignment.new_record?
          assignment.department = department
          assignment.position = position
          assignment.status = :active
          assignment.meta = {
            teaching_subjects: [],
            class_teacher_of: nil,
            additional_duties: []
          }
        end

        assignment.save!

        puts "\n已分配教師 #{teacher.email} 到 #{school.name} (#{academic_year.name})"
      rescue StandardError => e
        puts "\n處理教師 #{teacher.email} 時發生錯誤: #{e.message}"
        raise
      end
    end

    # 執行分配任務
    begin
      TeacherAssigner.assign_teachers(
        school_code: args[:school_code],
        academic_year_name: args[:academic_year_name],
        email_patterns: args[:email_patterns],
        department: args[:department],
        position: args[:position]
      )
    rescue StandardError => e
      puts "\n執行過程中發生錯誤:"
      puts e.message
      puts e.backtrace
    end
  end

  desc '顯示學校教師分配統計'
  task :show_teacher_stats, [:school_code] => :environment do |_task, args|
    school = School.find_by(code: args[:school_code])

    unless school
      puts "錯誤: 找不到學校代碼 #{args[:school_code]}"
      next
    end

    puts "\n=== #{school.name} 教師分配統計 ==="

    # 按學年顯示教師統計
    school.school_academic_years.order(start_date: :desc).each do |year|
      puts "\n學年: #{year.name}"

      # 獲取該學年的教師任教記錄
      assignments = year.teacher_assignments.includes(:general_user)
                        .select { |a| a.general_user.aienglish_user? && a.general_user.meta['aienglish_role'] == 'teacher' }

      if assignments.empty?
        puts '  暫無教師分配記錄'
        next
      end

      # 按部門分組統計
      puts "\n部門分佈:"
      assignments.group_by(&:department).each do |department, dept_assignments|
        puts "  #{department || '未分配部門'}:"
        puts "    教師人數: #{dept_assignments.count}"

        # 顯示職位分佈
        position_counts = dept_assignments.group_by(&:position)
                                          .transform_values(&:count)
        puts '    職位分佈:'
        position_counts.each do |position, count|
          puts "      - #{position || '未指定'}: #{count}人"
        end

        # 顯示郵箱域名分佈
        puts '    郵箱域名分佈:'
        email_domains = dept_assignments.map { |a| a.general_user.email.split('@').last }
        email_domains.tally.each do |domain, count|
          puts "      - @#{domain}: #{count}人"
        end
      end

      # 顯示教師列表（可選）
      puts "\n教師列表:"
      assignments.each do |assignment|
        teacher = assignment.general_user
        puts "  - #{teacher.email} (#{assignment.department}/#{assignment.position})"
      end
    end

    # 顯示總體統計
    puts "\n=== 總體統計 ==="
    total_assignments = TeacherAssignment.joins(:school_academic_year)
                                         .where(school_academic_years: { school_id: school.id })
                                         .includes(:general_user)
                                         .select { |a| a.general_user.aienglish_user? && a.general_user.meta['aienglish_role'] == 'teacher' }

    puts "總教師人數: #{total_assignments.map(&:general_user_id).uniq.count}"
    puts "總任教記錄數: #{total_assignments.count}"

    # 顯示跨學年任教的教師
    multi_year_teachers = total_assignments.group_by(&:general_user_id)
                                           .select { |_, assignments| assignments.count > 1 }

    if multi_year_teachers.any?
      puts "\n跨學年任教的教師:"
      multi_year_teachers.each do |_, assignments|
        teacher = assignments.first.general_user
        years = assignments.map { |a| a.school_academic_year.name }.join(', ')
        puts "  - #{teacher.email} (任教學年: #{years})"
      end
    end
  end
end
