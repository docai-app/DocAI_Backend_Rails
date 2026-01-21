# frozen_string_literal: true

class AssignmentStatisticsService
  def initialize(essay_assignment)
    @essay_assignment = essay_assignment
  end

  def calculate(class_name: nil, status: nil, name: nil, email: nil)
    query = @essay_assignment.assignment_student_assignments

    # 按班級過濾
    if class_name.present?
      query = query.joins(:general_user)
                   .joins('INNER JOIN student_enrollments ON student_enrollments.general_user_id = general_users.id')
                   .where(student_enrollments: { class_name: class_name, status: :active })
    end

    # 按狀態過濾
    query = query.where(status: status) if status.present?

    # 按名稱過濾
    if name.present?
      query = query.joins(:general_user) unless query.joins_values.include?(:general_user)
      query = query.where('general_users.nickname ILIKE ?', "%#{name}%")
    end

    # 按郵箱過濾
    if email.present?
      query = query.joins(:general_user) unless query.joins_values.include?(:general_user)
      query = query.where('general_users.email ILIKE ?', "%#{email}%")
    end

    total = query.count
    completed = query.completed.count
    pending = query.assigned.count
    overdue = query.overdue.count

    # 按班級統計
    by_class = calculate_by_class(query)

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
                             .includes(general_user: :student_enrollments)
                             .joins(:general_user)
                             .joins('INNER JOIN student_enrollments ON student_enrollments.general_user_id = general_users.id')
                             .joins('INNER JOIN school_academic_years ON school_academic_years.id = student_enrollments.school_academic_year_id')
                             .where(student_enrollments: { status: :active })
                             .where('school_academic_years.status = ?', SchoolAcademicYear.statuses[:active])

    if class_name.present?
      query = query.where(student_enrollments: { class_name: class_name })
    end

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

  def calculate_by_class(base_query)
    # 獲取所有相關的班級
    class_names = StudentEnrollment
      .joins(:general_user)
      .where(general_user_id: base_query.select(:general_user_id))
      .where(status: :active)
      .distinct
      .pluck(:class_name)

    class_names.map do |class_name|
      class_assignments = base_query.joins(:general_user)
                                   .joins('INNER JOIN student_enrollments ON student_enrollments.general_user_id = general_users.id')
                                   .where(student_enrollments: { class_name: class_name, status: :active })

      {
        class_name: class_name,
        total: class_assignments.count,
        completed: class_assignments.completed.count,
        pending: class_assignments.assigned.count,
        overdue: class_assignments.overdue.count
      }
    end
  end
end
