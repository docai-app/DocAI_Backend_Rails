# frozen_string_literal: true

module Schools
  # 儀表板統計生成器
  # 負責生成學校管理系統儀表板所需的統計數據
  class DashboardStatsGenerator
    # 初始化生成器
    # @param date_range [String] 可選的日期範圍過濾，格式為 "YYYY-MM-DD,YYYY-MM-DD"
    # @param school_id [Integer] 可選的學校ID過濾
    # @param academic_year [String] 可選的學年名稱過濾
    def initialize(date_range: nil, school_id: nil, academic_year: nil)
      @date_range = parse_date_range(date_range)
      @school_id = school_id
      @academic_year = academic_year
    end

    # 生成統計數據
    # @return [Hash] 統計數據
    def generate
      {
        summary: generate_summary,
        school_status: generate_school_status,
        student_trends: generate_student_trends,
        schools: generate_schools_list
      }
    end

    private

    # 解析日期範圍
    # @param date_range [String] 格式為 "YYYY-MM-DD,YYYY-MM-DD" 的日期範圍字符串
    # @return [Hash, nil] 包含 start_date 和 end_date 的哈希，或 nil
    def parse_date_range(date_range)
      return nil if date_range.blank?

      dates = date_range.split(',')
      return nil unless dates.length == 2

      begin
        {
          start_date: Date.parse(dates[0]),
          end_date: Date.parse(dates[1])
        }
      rescue ArgumentError
        nil
      end
    end

    # 生成摘要統計
    # @return [Hash] 摘要統計
    def generate_summary
      # 篩選學校
      schools_scope = filter_schools

      # 學校總數
      total_schools = schools_scope.count

      # 學年總數
      academic_years_scope = SchoolAcademicYear.where(school: schools_scope)
      academic_years_scope = filter_academic_years(academic_years_scope)
      total_academic_years = academic_years_scope.count

      # 學生人數
      total_students = count_students(academic_years_scope)

      # 教師人數
      total_teachers = count_teachers(academic_years_scope)

      {
        total_schools:,
        total_academic_years:,
        total_students:,
        total_teachers:
      }
    end

    # 生成學校狀態統計
    # @return [Hash] 學校狀態統計
    def generate_school_status
      # 篩選學校
      schools_scope = filter_schools

      # 按狀態分組計數
      status_counts = schools_scope.group(:status).count

      # 計算百分比
      total = status_counts.values.sum.to_f
      status_distribution = status_counts.map do |status, count|
        {
          status:,
          count:,
          percentage: total.zero? ? 0 : (count / total * 100).round(1)
        }
      end

      {
        active: status_counts['active'] || 0,
        inactive: status_counts['inactive'] || 0,
        status_distribution:
      }
    end

    # 生成學生人數趨勢
    # @return [Hash] 學生人數趨勢
    def generate_student_trends
      # 按學年分組獲取學生人數
      academic_years = SchoolAcademicYear.order(start_date: :asc).last(3)

      # 篩選學校
      academic_years = academic_years.where(school_id: @school_id) if @school_id.present?

      # 篩選特定學年
      academic_years = academic_years.where(name: @academic_year) if @academic_year.present?

      # 計算每個學年的學生人數
      labels = []
      data = []

      academic_years.each do |year|
        labels << year.name
        data << StudentEnrollment.where(school_academic_year: year).count
      end

      # 計算增長率
      growth_percentage = 0
      growth_percentage = ((data.last - data[-2]) / data[-2].to_f * 100).round(1) if data.length >= 2 && data[-2] > 0

      {
        labels:,
        data:,
        growth_percentage:
      }
    end

    # 生成學校列表
    # @return [Array<Hash>] 學校列表
    def generate_schools_list
      # 篩選學校
      schools_scope = filter_schools.limit(10) # 限制返回10個學校，避免數據過大

      schools_scope.map do |school|
        # 獲取該學校的所有學年
        academic_years = school.school_academic_years
        academic_years = filter_academic_years(academic_years)

        # 計算學生和教師數量
        student_count = count_students(academic_years)
        teacher_count = count_teachers(academic_years)

        {
          id: school.id,
          name: school.name,
          student_count:,
          teacher_count:,
          status: school.status,
          academic_years: academic_years.count
        }
      end
    end

    # 篩選學校
    # @return [ActiveRecord::Relation] 學校查詢對象
    def filter_schools
      scope = School.all

      # 按學校ID篩選
      scope = scope.where(id: @school_id) if @school_id.present?

      scope
    end

    # 篩選學年
    # @param scope [ActiveRecord::Relation] 學年查詢對象
    # @return [ActiveRecord::Relation] 篩選後的學年查詢對象
    def filter_academic_years(scope)
      # 按學年名稱篩選
      scope = scope.where(name: @academic_year) if @academic_year.present?

      # 按日期範圍篩選
      if @date_range.present?
        scope = scope.where('start_date >= ? OR end_date <= ?',
                            @date_range[:start_date],
                            @date_range[:end_date])
      end

      scope
    end

    # 計算學生人數
    # @param academic_years_scope [ActiveRecord::Relation] 學年查詢對象
    # @return [Integer] 學生總數
    def count_students(academic_years_scope)
      StudentEnrollment.where(school_academic_year: academic_years_scope).count
    end

    # 計算教師人數
    # @param academic_years_scope [ActiveRecord::Relation] 學年查詢對象
    # @return [Integer] 教師總數
    def count_teachers(academic_years_scope)
      TeacherAssignment.where(school_academic_year: academic_years_scope).count
    end
  end
end
