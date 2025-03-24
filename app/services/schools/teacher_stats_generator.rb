# frozen_string_literal: true

module Schools
  # 教師統計生成器
  # 負責生成學校教師統計信息
  class TeacherStatsGenerator
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
        # 獲取該學年的教師任教記錄
        assignments = year.teacher_assignments.includes(:general_user)
                          .select { |a| a.general_user.aienglish_user? && a.general_user.meta['aienglish_role'] == 'teacher' }

        # 按部門分組統計
        departments_stats = assignments.group_by(&:department).map do |department, dept_assignments|
          # 按職位分組
          positions = dept_assignments.group_by(&:position)
                                      .transform_values(&:count)
                                      .map { |position, count| { position:, count: } }

          # 郵箱域名統計
          email_domains = dept_assignments.map { |a| a.general_user.email.split('@').last }
          domain_stats = email_domains.tally.map { |domain, count| { domain:, count: } }

          {
            department: department || '未分配',
            teacher_count: dept_assignments.count,
            positions:,
            email_domains: domain_stats
          }
        end

        {
          id: year.id,
          name: year.name,
          status: year.status,
          teacher_count: assignments.count,
          departments: departments_stats,
          teachers: assignments.map { |a| teacher_info(a) },
          start_date: year.start_date,
          end_date: year.end_date
        }
      end
    end

    # 教師信息
    # @param assignment [TeacherAssignment] 任教記錄
    # @return [Hash] 教師信息
    def teacher_info(assignment)
      teacher = assignment.general_user
      {
        id: teacher.id,
        email: teacher.email,
        department: assignment.department,
        position: assignment.position,
        meta: assignment.meta
      }
    end

    # 整體統計
    # @return [Hash] 整體統計數據
    def overall_stats
      # 所有教師任教記錄
      all_assignments = TeacherAssignment.joins(:school_academic_year)
                                         .where(school_academic_years: { school_id: @school.id })
                                         .includes(:general_user)
                                         .select { |a| a.general_user.aienglish_user? && a.general_user.meta['aienglish_role'] == 'teacher' }

      # 所有教師用戶 ID
      all_teacher_ids = all_assignments.map(&:general_user_id).uniq

      # 按部門統計
      department_counts = all_assignments.group_by(&:department)
                                         .transform_values(&:count)
                                         .map { |dept, count| { department: dept, count: } }

      # 按職位統計
      position_counts = all_assignments.group_by(&:position)
                                       .transform_values(&:count)
                                       .map { |pos, count| { position: pos, count: } }

      # 多學年教師
      multi_year_teachers = find_multi_year_teachers(all_assignments)

      {
        total_teacher_count: all_teacher_ids.count,
        total_assignment_count: all_assignments.count,
        department_distribution: department_counts,
        position_distribution: position_counts,
        multi_year_teachers:
      }
    end

    # 尋找多學年教師
    # @param assignments [Array<TeacherAssignment>] 任教記錄
    # @return [Array<Hash>] 多學年教師信息
    def find_multi_year_teachers(assignments)
      # 按教師 ID 分組
      grouped = assignments.group_by(&:general_user_id)

      # 找出任教多個學年的教師
      multi_year_teachers = grouped.select { |_, teacher_assignments| teacher_assignments.count > 1 }

      multi_year_teachers.map do |teacher_id, teacher_assignments|
        teacher = teacher_assignments.first.general_user
        years = teacher_assignments.map { |a| a.school_academic_year.name }.join(', ')

        {
          id: teacher_id,
          email: teacher.email,
          years:
        }
      end
    end
  end
end
