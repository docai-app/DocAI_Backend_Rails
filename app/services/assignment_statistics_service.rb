# frozen_string_literal: true

class AssignmentStatisticsService
  def initialize(essay_assignment)
    @essay_assignment = essay_assignment
  end

  def calculate(class_name: nil, status: nil, name: nil, email: nil)
    # 使用 students_query 獲取所有符合條件的記錄（包含必要的關聯）
    base_query = students_query(
      class_name: class_name,
      status: status,
      name: name,
      email: email
    )

    # 加載所有記錄到內存，以便使用 overdue? 方法進行準確統計
    all_assignments = base_query.to_a

    # 批量預加載 EssayGrading 記錄以避免 N+1 查詢
    essay_gradings = EssayGrading.where(
      essay_assignment_id: all_assignments.map(&:essay_assignment_id).uniq,
      general_user_id: all_assignments.map(&:general_user_id).uniq
    ).where.not(status: 'draft')
                                  .index_by { |eg| [eg.essay_assignment_id, eg.general_user_id] }

    # 為每個 AssignmentStudentAssignment 設置緩存的 essay_grading
    all_assignments.each do |assignment|
      cached_grading = essay_gradings[[assignment.essay_assignment_id, assignment.general_user_id]]
      assignment.instance_variable_set(:@essay_grading, cached_grading) if cached_grading
    end

    # 根據實際狀態進行統計（考慮 overdue? 方法）
    # completed: 狀態為 completed 或已提交（has_submission?）
    # overdue: 未完成且逾期（overdue? 為 true）
    # pending: 未完成且未逾期
    total = all_assignments.count
    completed = all_assignments.count { |a| a.status == 'completed' || a.has_submission? }
    overdue = all_assignments.count { |a| a.status != 'completed' && !a.has_submission? && a.overdue? }
    pending = total - completed - overdue

    # 按班級統計
    by_class = calculate_by_class(all_assignments)

    {
      total_assigned: total,
      completed_count: completed,
      pending_count: pending,
      overdue_count: overdue,
      completion_rate: total.zero? ? 0.0 : (completed.to_f / total * 100).round(2),
      by_class: by_class
    }
  end

  def students_query(class_name: nil, status: nil, name: nil, email: nil)
    query = @essay_assignment.assignment_student_assignments
                             .includes(
                               general_user: :student_enrollments,
                               essay_assignment: []
                             )
                             .joins(:general_user)
                             .joins('INNER JOIN student_enrollments ON student_enrollments.general_user_id = general_users.id')
                             .where(
                               student_enrollments: {
                                 status: :active,
                                 school_academic_year_id: academic_year_id_for_assignment
                               }
                             )

    if class_name.present?
      query = query.where(student_enrollments: { class_name: class_name })
    end

    # 注意：status 過濾在這裡只作為初步過濾，最終統計會根據 overdue? 方法重新計算
    query = query.where(status: status) if status.present?

    # 按名稱過濾
    if name.present?
      query = query.where('general_users.nickname ILIKE ?', "%#{name}%")
    end

    # 按郵箱過濾
    if email.present?
      query = query.where('general_users.email ILIKE ?', "%#{email}%")
    end

    # 按班級、學號排序（學號從小到大）
    # 使用 CAST 將學號轉換為數字進行排序，如果轉換失敗則按字符串排序
    query.order(Arel.sql('student_enrollments.class_name ASC, 
                 CASE 
                   WHEN general_users.class_no ~ \'^[0-9]+$\' 
                   THEN CAST(general_users.class_no AS INTEGER) 
                   ELSE 999999 
                 END ASC,
                 general_users.class_no ASC'))
  end

  private

  def calculate_by_class(all_assignments)
    # 按班級分組統計
    # 需要從關聯中獲取班級信息
    class_groups = all_assignments.group_by do |assignment|
      enrollment = enrollment_for(assignment.general_user)
      enrollment&.class_name || 'Unknown'
    end

    class_groups.map do |class_name, assignments|
      total = assignments.count
      completed = assignments.count { |a| a.status == 'completed' || a.has_submission? }
      overdue = assignments.count { |a| a.status != 'completed' && !a.has_submission? && a.overdue? }
      pending = total - completed - overdue

      {
        class_name: class_name,
        total: total,
        completed: completed,
        pending: pending,
        overdue: overdue
      }
    end.sort_by { |item| item[:class_name] }
  end

  def academic_year_id_for_assignment
    @academic_year_id_for_assignment ||= @essay_assignment.school_academic_year_id ||
                                         @essay_assignment.general_user
                                                          .current_teaching_assignment
                                                          &.school_academic_year_id
  end

  def enrollment_for(student)
    student.student_enrollments.find do |enrollment|
      enrollment.school_academic_year_id == academic_year_id_for_assignment
    end
  end
end
