# frozen_string_literal: true

module Schools
  # 學生分配服務
  # 負責將 AI English 學生分配到指定學校和學年
  class StudentAssigner
    include ActiveModel::Model

    attr_reader :assigned_count, :skipped_count, :total_processed
    attr_accessor :school, :academic_year_name, :email_patterns

    validates :school, :academic_year_name, :email_patterns, presence: true

    # 執行學生分配流程
    # @return [Boolean] 成功或失敗
    def execute
      return false unless valid?

      @assigned_count = 0
      @skipped_count = 0
      @total_processed = 0

      # 查找學年
      @academic_year = school.school_academic_years.find_by(name: academic_year_name)
      unless @academic_year
        errors.add(:academic_year_name, "在學校 #{school.name} 中找不到學年 #{academic_year_name}")
        return false
      end

      ActiveRecord::Base.transaction do
        process_patterns
        true
      rescue StandardError => e
        errors.add(:base, e.message)
        Rails.logger.error("學生分配失敗: #{e.message}")
        false
      end
    end

    private

    # 處理所有郵箱模式
    def process_patterns
      patterns = email_patterns.split(';').map(&:strip)

      patterns.each do |pattern|
        process_single_pattern(pattern)
      end
    end

    # 處理單個郵箱模式
    # @param pattern [String] 郵箱模式
    def process_single_pattern(pattern)
      # 只查找 AI English 用戶
      users = GeneralUser.where('email LIKE ?', "%#{pattern}")
                         .select(&:aienglish_user?)

      users.each do |user|
        @total_processed += 1
        assign_single_user(user)
      end
    end

    # 分配單個用戶
    # @param user [GeneralUser] 用戶對象
    def assign_single_user(user)
      # 檢查用戶角色
      unless user.aienglish_user?
        @skipped_count += 1
        return
      end

      # 檢查用戶是否為教師
      is_teacher = user.meta['aienglish_role'] == 'teacher'
      if is_teacher
        @skipped_count += 1
        return # 教師不需要創建學生註冊記錄
      end

      # 創建或更新學生註冊記錄
      enrollment = StudentEnrollment.find_or_initialize_by(
        general_user: user,
        school_academic_year: @academic_year
      )

      # 如果是新記錄，設置班級信息
      if enrollment.new_record?
        enrollment.class_name = user.banbie.presence || '未分配'
        enrollment.class_number = user.class_no.presence || '未分配'
        enrollment.status = :active
        enrollment.save!

        # 更新該用戶的最近作業記錄
        update_essay_gradings(user, enrollment)

        @assigned_count += 1
      else
        @skipped_count += 1
      end
    end

    # 更新作業記錄的學校和學年信息
    # @param user [GeneralUser] 用戶對象
    # @param enrollment [StudentEnrollment] 註冊記錄
    def update_essay_gradings(user, enrollment)
      # 只更新最近30天的作業記錄
      recent_date = 30.days.ago
      user.essay_gradings
          .where('created_at > ?', recent_date)
          .find_each do |grading|
        grading.update!(
          submission_class_name: enrollment.class_name,
          submission_class_number: enrollment.class_number,
          submission_school_id: school.id,
          submission_academic_year_id: @academic_year.id
        )
      end
    end
  end
end
