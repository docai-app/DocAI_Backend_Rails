# frozen_string_literal: true

module Schools
  # 生成 School Impact Report 的统计数值（可用于前端对 mock payload 进行替换/覆盖）
  #
  # 返回结构建议：
  # - executive_metrics
  # - usage_trend
  # - assignment_type_usage
  # - class_usage
  # - high_volume_sessions
  # - months_in_range（用于 Classroom Snapshot 动态表头）
  class SchoolImpactReportGenerator
    # Classroom Snapshot 动态列最多展示 3 个自然月
    MAX_MONTHS_IN_RANGE = 3

    MODULE_CATEGORY_KEY_ORDER = %w[
      essay
      comprehension
      speaking_essay
      speaking_pronunciation
      speaking_conversation
      sentence_builder
    ].freeze

    # 前端 moduleBreakdown 对应表
    MODULE_KEY_BY_CATEGORY_KEY = {
      'essay' => 'writing',
      'comprehension' => 'comprehension',
      'speaking_essay' => 'speakingEssay',
      'speaking_pronunciation' => 'speakingPronunciation',
      'speaking_conversation' => 'speakingConversation',
      'sentence_builder' => 'sentenceBuilder'
    }.freeze

    CATEGORY_EN_LABEL = {
      'essay' => 'Essay Writing',
      'comprehension' => 'Reading Comprehension',
      'speaking_essay' => 'Speaking Essay',
      'speaking_pronunciation' => 'Speaking Pronunciation',
      'speaking_conversation' => 'Speaking Conversation',
      'sentence_builder' => 'Sentence Builder'
    }.freeze

    CATEGORY_ZH_LABEL = {
      'essay' => '作文寫作',
      'comprehension' => '閱讀理解',
      'speaking_essay' => '口說作文',
      'speaking_pronunciation' => '口說發音',
      'speaking_conversation' => '口說對話',
      'sentence_builder' => '句式建構'
    }.freeze

    # 初始化统计生成器。
    #
    # @param school_id [String] 学校 UUID
    # @param start_date [String, Date] 统计开始日期（含当天）
    # @param end_date [String, Date] 统计结束日期（含当天）
    # @param class_limit [Integer, nil] 班级榜单返回上限，默认 5
    #
    # @raise [ArgumentError] 当开始日期晚于结束日期时抛出
    def initialize(school_id:, start_date:, end_date:, class_limit: nil)
      @school_id = school_id.to_s
      @start_date = Date.parse(start_date.to_s)
      @end_date = Date.parse(end_date.to_s)
      raise ArgumentError, 'start_date must be <= end_date' if @start_date > @end_date

      @range_start_at = @start_date.beginning_of_day
      @range_end_at = @end_date.end_of_day

      @class_limit = (class_limit.presence || 5).to_i
      @class_limit = 5 if @class_limit <= 0
    end

    # 生成完整报表统计 payload（供 API controller 直接返回）。
    #
    # @return [Hash] 聚合统计结构，包含：
    #   - months_in_range
    #   - executive_metrics
    #   - usage_trend
    #   - assignment_type_usage
    #   - class_usage
    #   - high_volume_sessions
    def generate
      school = School.find(@school_id)

      months_in_range = build_months_in_range

      {
        months_in_range: months_in_range,
        executive_metrics: generate_executive_metrics(school),
        usage_trend: generate_usage_trend(school),
        assignment_type_usage: generate_assignment_type_usage(school),
        class_usage: generate_class_usage(school, months_in_range),
        high_volume_sessions: generate_high_volume_sessions(school)
      }
    end

    private

    # 生成报表期内覆盖到的自然月列表。
    #
    # 规则：
    # - 从 start_date 所在月的 1 号开始
    # - 到 end_date 所在月的 1 号结束
    # - 最多返回 MAX_MONTHS_IN_RANGE 个月
    #
    # @return [Array<Hash>] 每个月结构：yyyy_mm / month_index / zh_label / en_label
    def build_months_in_range
      months = []
      cursor = Date.new(@start_date.year, @start_date.month, 1)
      last_month = Date.new(@end_date.year, @end_date.month, 1)

      while cursor <= last_month && months.length < MAX_MONTHS_IN_RANGE
        months << cursor
        cursor = cursor.next_month
      end

      months.each_with_index.map do |m, idx|
        {
          yyyy_mm: m.strftime('%Y-%m'),
          month_index: idx + 1,
          zh_label: "#{m.month}月",
          en_label: m.strftime('%b')
        }
      end
    end

    # 生成 Executive Summary 顶部 KPI 统计。
    #
    # 指标口径：
    # - submissions_completed: EssayGrading.status = graded
    # - active_students: graded 提交去重学生数
    # - active_teachers: 关联作业创建者去重
    # - assignments_created: 报表期内创建且在本校产生 graded 提交的作业数
    # - completion_rate: 方案 A，completed_assigned / total_assigned
    #
    # @param school [School] 当前学校
    # @return [Hash] executive_metrics
    def generate_executive_metrics(school)
      # 以 “已完成评分 graded” 作为 submissions_completed 口径
      graded_submissions = EssayGrading
                             .where(submission_school_id: school.id, status: :graded)
                             .where(created_at: @range_start_at..@range_end_at)

      submissions_completed = graded_submissions.count
      # “活跃学生”：报表期内有提交（排除 draft）的人数
      active_students = EssayGrading
        .where(submission_school_id: school.id)
        .where(created_at: @range_start_at..@range_end_at)
        .where.not(status: :draft)
        .distinct
        .count(:general_user_id)

      active_teachers = graded_submissions
                           .joins(:essay_assignment)
                           .distinct
                           .count('essay_assignments.general_user_id')

      # assignments_created：统计报表期内创建，且在该学校有分配记录、并在期间产生过 graded submission 的作业
      assignments_created = graded_submissions
                                .joins(:essay_assignment)
                                .where('essay_assignments.created_at BETWEEN ? AND ?', @range_start_at, @range_end_at)
                                .distinct
                                .count('essay_assignments.id')

      # completion_rate (方案 A)：completed_assigned / total_assigned
      #
      # total_assigned：assignment_student_assignments.status in [assigned, completed]
      # 且 essay_assignment.created_at 在报表期内，同时 assignment_distributions.school_id 属于该学校
      completion_base = AssignmentStudentAssignment
                          .joins(:essay_assignment)
                          .joins(:assignment_distribution)
                          .where(assignment_distributions: { school_id: school.id })
                          .where(essay_assignments: { created_at: @range_start_at..@range_end_at })
                          .where(status: %i[assigned completed])

      total_assigned = completion_base.count
      completed_assigned = completion_base.where(status: :completed).count

      completion_rate = total_assigned.zero? ? 0 : ((completed_assigned.to_f / total_assigned) * 100).round

      # 当前学年在校学生数（SchoolAcademicYear.status=active 优先，否则用 today 落在 start/end 的学年）
      current_year = school.school_academic_years.active.order(start_date: :desc).first
      if current_year.nil?
        today = Time.zone.today
        current_year = school.school_academic_years
          .where('start_date <= ? AND end_date >= ?', today, today)
          .order(start_date: :desc)
          .first
      end

      enrolled_students_current_year =
        if current_year
          current_year.student_enrollments.active.count
        else
          0
        end

      active_students_share_pct =
        if enrolled_students_current_year.zero?
          0
        else
          ((active_students.to_f / enrolled_students_current_year) * 100).round
        end

      # 阅读理解（comprehension）提交量峰值月份（报表期内，排除 draft）
      reading_peak = EssayGrading
        .joins(:essay_assignment)
        .where(submission_school_id: school.id)
        .where(created_at: @range_start_at..@range_end_at)
        .where.not(status: :draft)
        .where(essay_assignments: { category: EssayAssignment.categories[:comprehension] })
        .select("date_trunc('month', essay_gradings.created_at) as month_start, COUNT(*) as submissions")
        .group('month_start')
        .order('submissions DESC')
        .first

      reading_peak_yyyy_mm = reading_peak&.month_start&.to_date&.strftime('%Y-%m')

      {
        active_students: active_students.to_i,
        active_teachers: active_teachers.to_i,
        assignments_created: assignments_created.to_i,
        submissions_completed: submissions_completed.to_i,
        completion_rate: completion_rate.to_i,

        # 用于替换 mock note：
        # “报表期内约占在校学生 XX%”
        enrolled_students_current_year: enrolled_students_current_year.to_i,
        active_students_share_pct: active_students_share_pct.to_i,
        # 用于替换 mock note：
        # “X 月份整体班级使用更趋稳定”（这里以阅读理解提交峰值月份做稳定描述锚点）
        reading_peak_month_yyyy_mm: reading_peak_yyyy_mm
      }
    end

    # 生成每周趋势（usage trend）。
    #
    # 按周聚合（week_start = date_trunc('week', created_at)），输出每周：
    # - submissions
    # - active_students
    # - active_teachers
    # 以及中英文周标签，供前端图表与表格直接使用。
    #
    # @param school [School] 当前学校
    # @return [Array<Hash>] usage_trend
    def generate_usage_trend(school)
      rel = EssayGrading
        .joins(:essay_assignment)
        .where(submission_school_id: school.id, status: :graded, created_at: @range_start_at..@range_end_at)
        .select(
          'date_trunc(\'week\', essay_gradings.created_at) as week_start',
          'COUNT(*) as submissions',
          'COUNT(DISTINCT essay_gradings.general_user_id) as active_students',
          'COUNT(DISTINCT essay_assignments.general_user_id) as active_teachers'
        )
        .group('week_start')
        .order('week_start ASC')

      rel.map do |row|
        ws = row.week_start.to_date
        we = (row.week_start.to_date + 6.days)

        {
          week_start: ws.strftime('%Y-%m-%d'),
          week_end: we.strftime('%Y-%m-%d'),
          week_label_en: "#{ws.strftime('%b')} #{ws.day} - #{we.strftime('%b')} #{we.day}",
          week_label_zh: "#{ws.month}月#{ws.day}日 - #{we.month}月#{we.day}日",
          active_students: row.active_students.to_i,
          active_teachers: row.active_teachers.to_i,
          submissions: row.submissions.to_i
        }
      end
    end

    # 生成模块维度使用分布（assignment type usage）。
    #
    # 以 EssayAssignment.category 聚合，统计：
    # - assignments：去重作业数
    # - submissions：提交数
    #
    # 并按 MODULE_CATEGORY_KEY_ORDER 固定输出顺序，保证前端展示稳定。
    #
    # @param school [School] 当前学校
    # @return [Array<Hash>] assignment_type_usage
    def generate_assignment_type_usage(school)
      # 只统计报表期内产生 graded submission 的作业类别
      rel = EssayGrading
        .joins(:essay_assignment)
        .where(submission_school_id: school.id, status: :graded, created_at: @range_start_at..@range_end_at)
        .group('essay_assignments.category')
        .select(
          'essay_assignments.category as category_value',
          'COUNT(*) as submissions',
          'COUNT(DISTINCT essay_assignments.id) as assignments'
        )

      # 把 DB 返回的 category_value -> category_key 映射回
      by_key = rel.each_with_object({}) do |row, acc|
        category_key = EssayAssignment.categories.invert[row.category_value]
        acc[category_key] = {
          category_key: category_key,
          assignments: row.assignments.to_i,
          submissions: row.submissions.to_i
        }
      end

      MODULE_CATEGORY_KEY_ORDER.map do |key|
        entry = by_key[key] || { category_key: key, assignments: 0, submissions: 0 }

        entry.merge(
          category_en: CATEGORY_EN_LABEL[key],
          category_zh: CATEGORY_ZH_LABEL[key]
        )
      end
    end

    # 生成班级快照（Classroom Snapshot）统计。
    #
    # 内容包含：
    # - month_submissions: 各自然月提交量数组（按 months_in_range 顺序）
    # - submissions_total: 月提交总和
    # - module_breakdown: 各模块提交量
    #
    # 最终按 submissions_total 倒序，并截断到 @class_limit。
    #
    # @param school [School] 当前学校
    # @param months_in_range [Array<Hash>] build_months_in_range 的结果
    # @return [Array<Hash>] class_usage
    def generate_class_usage(school, months_in_range)
      months = months_in_range.map { |m| m[:yyyy_mm] }

      month_start_dates = months_in_range.map do |m|
        Date.parse("#{m[:yyyy_mm]}-01")
      end

      month_start_to_index = {}
      month_start_dates.each_with_index { |d, idx| month_start_to_index[d] = idx }

      graded_submissions = EssayGrading
                              .where(submission_school_id: school.id, status: :graded)
                              .where(created_at: @range_start_at..@range_end_at)
                              .where.not(submission_class_name: [nil, ''])

      # 每个 class 在每个自然月的 submissions 数（用于 month_submissions[]）
      monthly_rows = graded_submissions
        .joins(:essay_assignment)
        .select(
          'essay_gradings.submission_class_name as class_name',
          'date_trunc(\'month\', essay_gradings.created_at) as month_start',
          'COUNT(*) as submissions'
        )
        .group('essay_gradings.submission_class_name', 'month_start')

      # 每个 class 在整个区间内各 module 的 breakdown（总量，不按月拆）
      module_rows = graded_submissions
        .joins(:essay_assignment)
        .select(
          'essay_gradings.submission_class_name as class_name',
          'essay_assignments.category as category_value',
          'COUNT(*) as submissions'
        )
        .group('essay_gradings.submission_class_name', 'essay_assignments.category')

      class_map = {}

      monthly_rows.each do |r|
        class_name = r.class_name.to_s
        month_start_date = r.month_start.to_date
        month_idx = month_start_to_index[month_start_date]
        next if month_idx.nil?

        class_map[class_name] ||= {
          class_name: class_name,
          month_submissions: Array.new(months.length, 0),
          submissions_total: 0,
          module_breakdown: {
            'writing' => 0,
            'comprehension' => 0,
            'speakingEssay' => 0,
            'speakingPronunciation' => 0,
            'speakingConversation' => 0,
            'sentenceBuilder' => 0
          }
        }

        class_map[class_name][:month_submissions][month_idx] = r.submissions.to_i
      end

      module_rows.each do |r|
        class_name = r.class_name.to_s
        category_key = EssayAssignment.categories.invert[r.category_value]
        module_key = MODULE_KEY_BY_CATEGORY_KEY[category_key]
        next if module_key.nil?

        class_map[class_name] ||= {
          class_name: class_name,
          month_submissions: Array.new(months.length, 0),
          submissions_total: 0,
          module_breakdown: {
            'writing' => 0,
            'comprehension' => 0,
            'speakingEssay' => 0,
            'speakingPronunciation' => 0,
            'speakingConversation' => 0,
            'sentenceBuilder' => 0
          }
        }

        class_map[class_name][:module_breakdown][module_key] = r.submissions.to_i
      end

      # submissions_total：month_submissions 求和
      class_map.each do |_k, v|
        v[:submissions_total] = v[:month_submissions].sum
      end

      class_map.values
        .sort_by { |v| -v[:submissions_total] }
        .first(@class_limit)
    end

    # 生成高密度提交时段（30 分钟窗口内提交 > 10）。
    #
    # 规则：
    # - 将创建时间按 30 分钟分桶
    # - 按 作业 + 教师 + 班级 + 时间桶 聚合
    # - 仅保留 submissions_in_30_minutes > 10 的记录
    # - 按提交量降序输出
    #
    # @param school [School] 当前学校
    # @return [Array<Hash>] high_volume_sessions
    def generate_high_volume_sessions(school)
      # 30分钟窗口桶：floor 到 30 分钟
      # 注意：PostgreSQL interval 计算需使用 raw SQL
      bucket_expr = "date_trunc('hour', essay_gradings.created_at) + (floor(extract(minute from essay_gradings.created_at)/30) * interval '30 minutes')"

      rel = EssayGrading
        .joins(essay_assignment: :general_user)
        .where(submission_school_id: school.id, status: :graded, created_at: @range_start_at..@range_end_at)
        .select(
          'essay_assignments.id as essay_assignment_id',
          'essay_assignments.title as assignment_title',
          'general_users.nickname as teacher_name',
          'essay_gradings.submission_class_name as class_name',
          "#{bucket_expr} as bucket_start",
          'COUNT(*) as submissions_in_30_minutes'
        )
        .group('essay_assignments.id', 'essay_assignments.title', 'general_users.nickname', 'essay_gradings.submission_class_name', 'bucket_start')
        .having('COUNT(*) > 10')
        .order('submissions_in_30_minutes DESC')

      rel.map do |row|
        bucket_start = row.bucket_start.to_time
        bucket_end = bucket_start + 30.minutes

        {
          assignment_title: row.assignment_title.to_s,
          teacher_name: row.teacher_name.to_s,
          session_window: "#{bucket_start.strftime('%Y-%m-%d %H:%M')}-#{bucket_end.strftime('%H:%M')}",
          submissions_in_30_minutes: row.submissions_in_30_minutes.to_i,
          class_name: row.class_name.to_s
        }
      end
    end
  end
end

