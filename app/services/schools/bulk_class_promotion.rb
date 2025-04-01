# app/services/schools/bulk_class_promotion.rb
# frozen_string_literal: true

module Schools
  # 批量升班服務
  # 負責將學生批量升級到新的學年和班級
  class BulkClassPromotion
    include ActiveModel::Model

    attr_reader :total_processed, :success_count, :failed_count, :promotion_errors
    attr_accessor :school, :source_academic_year, :target_academic_year, :promotion_rules

    validates :school, :source_academic_year, :target_academic_year, :promotion_rules, presence: true

    # 初始化升班服務
    # @param school [School] 學校對象
    # @param source_academic_year [SchoolAcademicYear] 源學年
    # @param target_academic_year [SchoolAcademicYear] 目標學年
    # @param promotion_rules [Hash] 升班規則，包含 class_rules 和 number_rules
    def initialize(school, source_academic_year, target_academic_year, promotion_rules)
      @school = school
      @source_academic_year = source_academic_year
      @target_academic_year = target_academic_year
      @promotion_rules = promotion_rules
      @total_processed = 0
      @success_count = 0
      @failed_count = 0
      @promotion_errors = {}
      @processed_students = {} # 跟踪已處理的學生，避免重複處理
    end

    # 執行批量升班流程
    # @return [Boolean] 成功或失敗
    def execute
      return false unless valid?

      # 不使用單一事務，分兩階段執行
      begin
        # 第一階段：處理現有記錄（更改狀態）
        deactivate_existing_enrollments

        # 第二階段：創建新記錄
        process_promotions

        true
      rescue StandardError => e
        errors.add(:base, e.message)
        Rails.logger.error("批量升班失敗: #{e.message}")
        false
      end
    end

    private

    # 第一階段：將所有現有記錄設為非活躍狀態
    def deactivate_existing_enrollments
      Rails.logger.info('==== 批量升班階段1：處理現有記錄 ====')

      # 獲取源學年的所有待升班學生
      source_students = source_academic_year.student_enrollments
                                            .includes(:general_user)
                                            .where(status: :active)
                                            .map(&:general_user_id)

      # 查找這些學生在目標學校的所有活躍記錄
      existing_enrollments = StudentEnrollment.joins(:school_academic_year)
                                              .where(general_user_id: source_students)
                                              .where(status: :active)
                                              .where(school_academic_years: { school_id: @school.id })

      # 記錄學生清單
      Rails.logger.info("共發現 #{existing_enrollments.count} 個需要處理的現有記錄")

      # 使用 update_all 批量更新，避開驗證和回調
      existing_enrollments.update_all(
        status: StudentEnrollment.statuses[:promoted],
        updated_at: Time.current
      )

      # 為每個學生記錄更新原因（使用單獨的循環避免大量數據問題）
      existing_enrollments.find_each do |enrollment|
        # 僅更新元數據字段
        meta = enrollment.meta || {}
        meta['promotion_reason'] = "批量升班到#{target_academic_year.name}"
        meta['promoted_at'] = Time.current.as_json
        enrollment.update_column(:meta, meta)
      end

      Rails.logger.info("已將 #{existing_enrollments.count} 個記錄狀態更新為 promoted")
    end

    # 第二階段：處理所有升班
    def process_promotions
      Rails.logger.info('==== 批量升班階段2：創建新記錄 ====')

      # 獲取源學年的所有學生
      source_enrollments = source_academic_year.student_enrollments
                                               .includes(:general_user)
                                               .where(status: %i[active promoted]) # 包括已經在第一階段被標記為promoted的記錄

      Rails.logger.info("處理 #{source_enrollments.count} 名學生的升班")

      source_enrollments.each do |enrollment|
        # 避免重複處理同一學生
        next if @processed_students[enrollment.general_user_id]

        process_single_promotion(enrollment)
        @processed_students[enrollment.general_user_id] = true
      end
    end

    # 處理單個學生的升班
    # @param enrollment [StudentEnrollment] 學生註冊記錄
    def process_single_promotion(enrollment)
      @total_processed += 1

      # 獲取學生的當前班級信息
      current_class = enrollment.class_name
      current_number = enrollment.class_number

      # 根據升班規則計算新的班級信息
      new_class_info = calculate_new_class(current_class, current_number)

      # 檢查學生在目標學年是否已有記錄
      existing_enrollment = StudentEnrollment.find_by(
        general_user_id: enrollment.general_user_id,
        school_academic_year_id: target_academic_year.id
      )

      if existing_enrollment.present?
        # 更新現有記錄
        Rails.logger.info("更新學生 #{enrollment.general_user.email} 的現有目標學年記錄")

        begin
          # 直接更新記錄，狀態已在第一階段處理
          existing_enrollment.assign_attributes(
            class_name: new_class_info[:class_name],
            class_number: new_class_info[:class_number],
            status: :active, # 設置為活躍狀態
            meta: existing_enrollment.meta.merge(
              {
                promoted_from: {
                  enrollment_id: enrollment.id,
                  academic_year_id: source_academic_year.id,
                  academic_year_name: source_academic_year.name,
                  class_name: current_class,
                  class_number: current_number,
                  promoted_at: Time.current
                }
              }
            )
          )

          if existing_enrollment.save
            @success_count += 1

            # 確保源記錄被標記為已升班（如果還未標記）
            if enrollment.active?
              enrollment.update_column(:status, StudentEnrollment.statuses[:promoted])
              meta = enrollment.meta || {}
              meta['promotion_reason'] = "批量升班到#{target_academic_year.name}"
              meta['promoted_at'] = Time.current.as_json
              enrollment.update_column(:meta, meta)
            end
          else
            @failed_count += 1
            @promotion_errors[enrollment.general_user.email] = existing_enrollment.errors.full_messages.join(', ')
            Rails.logger.error("更新學生 #{enrollment.general_user.email} 失敗: #{existing_enrollment.errors.full_messages}")
          end
        rescue StandardError => e
          @failed_count += 1
          @promotion_errors[enrollment.general_user.email] = e.message
          Rails.logger.error("更新學生 #{enrollment.general_user.email} 時發生錯誤: #{e.message}")
        end
      else
        # 創建新的註冊記錄
        begin
          # 創建新記錄
          new_enrollment = StudentEnrollment.new(
            general_user: enrollment.general_user,
            school_academic_year: target_academic_year,
            class_name: new_class_info[:class_name],
            class_number: new_class_info[:class_number],
            status: :active,
            meta: {
              promoted_from: {
                enrollment_id: enrollment.id,
                academic_year_id: source_academic_year.id,
                academic_year_name: source_academic_year.name,
                class_name: current_class,
                class_number: current_number,
                promoted_at: Time.current
              }
            }
          )

          if new_enrollment.save
            @success_count += 1

            # 確保源記錄被標記為已升班（如果還未標記）
            if enrollment.active?
              enrollment.update_column(:status, StudentEnrollment.statuses[:promoted])
              meta = enrollment.meta || {}
              meta['promotion_reason'] = "批量升班到#{target_academic_year.name}"
              meta['promoted_at'] = Time.current.as_json
              enrollment.update_column(:meta, meta)
            end
          else
            @failed_count += 1
            @promotion_errors[enrollment.general_user.email] = new_enrollment.errors.full_messages.join(', ')
            Rails.logger.error("創建學生 #{enrollment.general_user.email} 的新記錄失敗: #{new_enrollment.errors.full_messages}")
          end
        rescue StandardError => e
          @failed_count += 1
          @promotion_errors[enrollment.general_user.email] = e.message
          Rails.logger.error("創建學生 #{enrollment.general_user.email} 的新記錄時發生錯誤: #{e.message}")
        end
      end
    rescue StandardError => e
      @failed_count += 1
      @promotion_errors[enrollment.general_user.email] = e.message
      Rails.logger.error("處理學生 #{enrollment.general_user.email} 升班時發生錯誤: #{e.message}")
    end

    # 計算新的班級信息
    # @param current_class [String] 當前班級
    # @param current_number [String] 當前班號
    # @return [Hash] 新的班級信息
    def calculate_new_class(current_class, current_number)
      # 根據升班規則計算新班級
      new_class = promotion_rules[:class_rules][current_class] || current_class
      new_number = promotion_rules[:number_rules][current_number] || current_number

      {
        class_name: new_class,
        class_number: new_number
      }
    end
  end
end
