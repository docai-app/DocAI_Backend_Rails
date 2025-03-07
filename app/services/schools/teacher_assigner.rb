module Schools
  # 教師分配服務
  # 負責將 AI English 教師分配到指定學校和學年
  class TeacherAssigner
    include ActiveModel::Model

    attr_reader :assigned_count, :skipped_count, :total_processed
    attr_accessor :school, :academic_year_name, :email_patterns,
                  :department, :position

    validates :school, :academic_year_name, :email_patterns,
              :department, :position, presence: true

    # 執行教師分配流程
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
        Rails.logger.error("教師分配失敗: #{e.message}")
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
      # 只查找 AI English 教師
      teachers = GeneralUser.where('email LIKE ?', "%#{pattern}")
                            .select { |user| user.aienglish_user? && user.meta['aienglish_role'] == 'teacher' }

      teachers.each do |teacher|
        @total_processed += 1
        assign_single_teacher(teacher)
      end
    end

    # 分配單個教師
    # @param teacher [GeneralUser] 教師對象
    def assign_single_teacher(teacher)
      # 檢查用戶角色
      unless teacher.aienglish_user? && teacher.meta['aienglish_role'] == 'teacher'
        @skipped_count += 1
        return
      end

      # 創建或更新教師任教記錄
      assignment = TeacherAssignment.find_or_initialize_by(
        general_user: teacher,
        school_academic_year: @academic_year
      )

      if assignment.new_record?
        assignment.department = department
        assignment.position = position
        assignment.status = :active
        assignment.meta = {
          teaching_subjects: [],
          class_teacher_of: nil,
          additional_duties: []
        }
        assignment.save!

        @assigned_count += 1
      else
        @skipped_count += 1
      end
    end
  end
end
