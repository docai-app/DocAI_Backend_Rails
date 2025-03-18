# frozen_string_literal: true

module Schools
  # 學生統計生成器
  # 負責生成學校學生統計信息
  class StudentStatsGenerator
    # 初始化生成器
    # @param school [School] 學校對象
    def initialize(school)
      @school = school
    end

    # 生成統計數據
    # @return [Hash] 統計數據
    def generate
      {
        school: school_info,
        academic_years: academic_years_stats,
        overall: overall_stats
      }
    end

    private

    # 學校基本信息
    # @return [Hash] 學校信息
    def school_info
      {
        id: @school.id,
        name: @school.name,
        code: @school.code,
        status: @school.status,
        region: @school.meta['region'],
        school_type: @school.meta['school_type']
      }
    end

    # 各學年統計
    # @return [Array<Hash>] 學年統計數組
    def academic_years_stats
      @school.school_academic_years.order(start_date: :desc).map do |year|
        # 獲取該學年的學生註冊記錄
        enrollments = year.student_enrollments.includes(:general_user)
                          .select { |e| e.general_user.aienglish_user? && e.general_user.meta['aienglish_role'] != 'teacher' }

        # 按班級分組統計
        classes_stats = enrollments.group_by(&:class_name).map do |class_name, class_enrollments|
          # 郵箱域名統計
          email_domains = class_enrollments.map { |e| e.general_user.email.split('@').last }
          domain_stats = email_domains.tally.map { |domain, count| { domain:, count: } }

          {
            class_name: class_name || '未分配',
            student_count: class_enrollments.count,
            email_domains: domain_stats
          }
        end

        {
          id: year.id,
          name: year.name,
          status: year.status,
          student_count: enrollments.count,
          classes: classes_stats,
          start_date: year.start_date,
          end_date: year.end_date
        }
      end
    end

    # 整體統計
    # @return [Hash] 整體統計數據
    def overall_stats
      # 所有學生註冊記錄
      all_enrollments = StudentEnrollment.joins(:school_academic_year)
                                         .where(school_academic_years: { school_id: @school.id })
                                         .includes(:general_user)
                                         .select { |e| e.general_user.aienglish_user? && e.general_user.meta['aienglish_role'] != 'teacher' }

      # 所有學生用戶 ID
      all_student_ids = all_enrollments.map(&:general_user_id).uniq

      # 分年級學生數量
      grade_counts = count_by_grade(all_enrollments)

      # 多學年學生
      multi_year_students = find_multi_year_students(all_enrollments)

      {
        total_student_count: all_student_ids.count,
        total_enrollment_count: all_enrollments.count,
        grade_distribution: grade_counts,
        multi_year_student_count: multi_year_students.count
      }
    end

    # 按年級統計
    # @param enrollments [Array<StudentEnrollment>] 註冊記錄
    # @return [Hash] 年級分布
    def count_by_grade(enrollments)
      grade_pattern = /\d+/

      enrollments.each_with_object(Hash.new(0)) do |enrollment, counts|
        # 嘗試從班級名稱中提取年級
        grade_match = enrollment.class_name.match(grade_pattern)
        grade = grade_match ? grade_match[0] : '未知'
        counts[grade] += 1
      end.sort.to_h
    end

    # 尋找多學年學生
    # @param enrollments [Array<StudentEnrollment>] 註冊記錄
    # @return [Array<Hash>] 多學年學生信息
    def find_multi_year_students(enrollments)
      # 按學生 ID 分組
      grouped = enrollments.group_by(&:general_user_id)

      # 找出註冊多個學年的學生
      multi_year_students = grouped.select { |_, student_enrollments| student_enrollments.count > 1 }

      multi_year_students.map do |student_id, student_enrollments|
        student = student_enrollments.first.general_user
        years = student_enrollments.map { |e| e.school_academic_year.name }.join(', ')

        {
          id: student_id,
          email: student.email,
          years:
        }
      end
    end
  end
end
