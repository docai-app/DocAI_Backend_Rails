# frozen_string_literal: true

class AdminNotificationMailer < ApplicationMailer
  # Independent host watchdog uses existing SMTP, not the potentially lost queue.
  def reliability_health_alert(issues)
    mail(to: ENV.fetch('ADMIN_NOTIFICATION_EMAIL', 'Bobby.lian@docai.net'),
         subject: '【需人工處理】AI English 排程／worker 健康檢查未通過') do |format|
      format.text { render plain: "請工程師立即核對報告及失聯恢復排程。\n#{Array(issues).join("\n")}\n這不是批量重跑授權；請勿清空 Redis 或倒填啟用時間。" }
    end
  end

  def operations_status_report(summary)
    @report = summary
    @needs_attention = summary.fetch('alert_count').positive? || summary.fetch('warnings').any?
    ending = Time.iso8601(summary.fetch('period_end')).in_time_zone('Asia/Macau').strftime('%m/%d %H:%M')
    prefix = @needs_attention ? "【需人工處理 #{summary['alert_count']} 項／請查看警告】" : '【運行摘要】'
    mail(to: ENV.fetch('ADMIN_NOTIFICATION_EMAIL', 'Bobby.lian@docai.net'),
         subject: "#{prefix} AI English 狀態報告 · #{ending} 澳門時間")
  end

  # 发送任务停止通知给管理员
  # @param essay_grading [EssayGrading] 评分任务对象
  def assignment_stopped_notification(essay_grading, generation: nil)
    @generation = generation
    @recovery_attention = generation&.state == 'unknown' && generation&.attention_required_at.present?
    @notification_title = if @recovery_attention
                            'Assignment Needs Review'
                          else
                            generation&.kind == 'supplement' ? 'Supplementary Exercise Failed' : 'Assignment Stopped Notification'
                          end
    @essay_grading = essay_grading
    @user = essay_grading.general_user
    @assignment = essay_grading.essay_assignment
    
    # 获取管理员邮箱地址
    admin_email = ENV.fetch('ADMIN_NOTIFICATION_EMAIL', 'Bobby.lian@docai.net')
    
    subject = "#{@notification_title} - User: #{@user.email}, Assignment: #{@assignment.title}"
    
    mail(
      to: admin_email,
      subject: subject
    )
  end
end
