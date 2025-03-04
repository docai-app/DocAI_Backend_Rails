# lib/tasks/school_management.rake
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
      }

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
      }

      # 定義默認時區
      TIMEZONE_BY_REGION = {
        'hk' => 'Asia/Hong_Kong',
        'mo' => 'Asia/Macau'
      }

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
        STDIN.gets.chomp
      end

      def self.prompt_with_options(message, options)
        puts "\n#{message}:"
        options.each_with_index do |option, index|
          puts "#{index + 1}. #{option}"
        end
        print "請選擇 (1-#{options.length}): "

        choice = STDIN.gets.chomp.to_i
        return options[choice - 1] if choice.between?(1, options.length)

        options.first # 返回默認選項
      end

      def self.prompt_with_default(message, default)
        print "#{message} [#{default}]: "
        input = STDIN.gets.chomp
        input.empty? ? default : input
      end

      def self.gather_custom_settings
        custom_settings = {}

        puts "\n是否添加自定義設置？(y/n)"
        return custom_settings unless STDIN.gets.chomp.downcase == 'y'

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
end
