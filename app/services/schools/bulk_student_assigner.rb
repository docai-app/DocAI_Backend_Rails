module Schools
  # 批量學生分配服務
  # 負責將學生批量分配到多個學校和學年
  class BulkStudentAssigner
    include ActiveModel::Model

    attr_reader :total_processed, :success_count, :failed_count, :assignment_errors
    attr_accessor :assignments

    validates :assignments, presence: true

    # 初始化批量分配器
    # @param assignments [Array<Hash>] 分配信息數組
    def initialize(assignments)
      @assignments = assignments
      @total_processed = 0
      @success_count = 0
      @failed_count = 0
      @assignment_errors = {}
    end

    # 執行批量分配流程
    # @return [Boolean] 成功或失敗
    def execute
      return false unless valid?

      begin
        process_assignments
        true
      rescue StandardError => e
        errors.add(:base, e.message)
        Rails.logger.error("批量學生分配失敗: #{e.message}")
        false
      end
    end

    private

    # 處理所有分配
    def process_assignments
      @assignments.each_with_index do |assignment, index|
        school = School.find_by(code: assignment[:school_code])

        unless school
          @failed_count += 1
          @assignment_errors[index] = "找不到學校代碼: #{assignment[:school_code]}"
          next
        end

        assigner = StudentAssigner.new(
          school:,
          academic_year_name: assignment[:academic_year_name],
          email_patterns: assignment[:email_patterns]
        )

        if assigner.execute
          @total_processed += assigner.total_processed
          @success_count += 1
        else
          @failed_count += 1
          @assignment_errors[index] = assigner.errors.full_messages.join(', ')
        end
      rescue StandardError => e
        @failed_count += 1
        @assignment_errors[index] = e.message
        Rails.logger.error("處理第 #{index + 1} 個分配時發生錯誤: #{e.message}")
      end
    end
  end
end
