# frozen_string_literal: true

class AssignmentReminderMailer < ApplicationMailer
  def remind_student(student, essay_assignment, deadline)
    @student = student
    @essay_assignment = essay_assignment
    @deadline = deadline
    @days_remaining = deadline.present? ? ((deadline - Time.current) / 1.day).ceil : nil
    
    # 构建作业详情链接
    # 使用作业 code 构建链接，学生可以通过 code 访问作业
    frontend_base_url = ENV.fetch('FRONTEND_URL', 'https://aienglish.docai.net')
    if @essay_assignment.code.present?
      # 根据作业类别构建不同的 URL
      category_routes = {
        'essay' => '/essay/upload',
        'comprehension' => '/comprehension/upload',
        'speaking_conversation' => '/speaking/conversation/upload',
        'speaking_essay' => '/speaking/essay/upload',
        'sentence_builder' => '/sentence_building/upload',
        'speaking_pronunciation' => '/speaking_pronunciation/upload'
      }
      route_prefix = category_routes[@essay_assignment.category] || '/essay/upload'
      @assignment_url = "#{frontend_base_url}#{route_prefix}/#{@essay_assignment.code}"
    else
      # 如果没有 code，链接到作业列表页面
      @assignment_url = "#{frontend_base_url}/essay/grade"
    end

    mail(
      to: @student.email,
      subject: "Assignment Reminder: #{@essay_assignment.title}"
    )
  end
end
