# frozen_string_literal: true

class AssignmentReminderService
  Result = Struct.new(:success?, :reminders_sent, :reminders_failed, :reminders, :failed_students, :error_message, keyword_init: true)

  def initialize(essay_assignment, sender)
    @essay_assignment = essay_assignment
    @sender = sender
  end

  def send_reminders(target_students: nil)
    # 獲取需要發送提醒的學生
    students_to_remind = if target_students.present?
      GeneralUser.where(id: target_students)
    else
      @essay_assignment.assignment_student_assignments
                      .where(status: [:assigned, :overdue])
                      .includes(:general_user)
                      .map(&:general_user)
                      .compact
    end

    return Result.new(success?: false, error_message: 'No students to remind') if students_to_remind.empty?

    reminders = []
    failed_students = []

    students_to_remind.each do |student|
      begin
        reminder = AssignmentReminder.create!(
          essay_assignment: @essay_assignment,
          general_user: student,
          reminder_sender: @sender,
          reminder_type: :email,
          status: :pending
        )
        
        # 發送郵件（異步）
        begin
          assignment = @essay_assignment.assignment_student_assignments
                                        .find_by(general_user_id: student.id)
          deadline = assignment&.deadline

          AssignmentReminderMailer.remind_student(
            student,
            @essay_assignment,
            deadline
          ).deliver_later

          reminder.update_columns(status: AssignmentReminder.statuses[:sent], sent_at: Time.current)
          reminders << reminder
        rescue StandardError => e
          Rails.logger.error "Failed to send email reminder for student #{student.id}: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
          reminder.update_columns(status: AssignmentReminder.statuses[:failed])
          failed_students << {
            student_id: student.id,
            student_name: student.nickname,
            student_email: student.email,
            error: e.message
          }
        end
      rescue StandardError => e
        Rails.logger.error "Failed to create reminder for student #{student.id}: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        failed_students << {
          student_id: student.id,
          student_name: student.nickname,
          student_email: student.email,
          error: "Failed to create reminder: #{e.message}"
        }
      end
    end

    Result.new(
      success?: true,
      reminders_sent: reminders.count,
      reminders_failed: failed_students.count,
      reminders: reminders,
      failed_students: failed_students
    )
  end
end
