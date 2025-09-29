# frozen_string_literal: true

class AdminNotificationMailer < ApplicationMailer
  # 发送任务停止通知给管理员
  # @param essay_grading [EssayGrading] 评分任务对象
  def assignment_stopped_notification(essay_grading)
    @essay_grading = essay_grading
    @user = essay_grading.general_user
    @assignment = essay_grading.essay_assignment
    
    # 获取管理员邮箱地址
    admin_email = ENV.fetch('ADMIN_NOTIFICATION_EMAIL', 'Bobby.lian@docai.net')
    
    subject = "Assignment Stopped Notification - User: #{@user.email}, Assignment: #{@assignment.title}"
    
    mail(
      to: admin_email,
      subject: subject
    )
  end
end