# frozen_string_literal: true

# == Schema Information
#
# Table name: public.general_users
#
#  id                     :uuid             not null, primary key
#  email                  :string
#  encrypted_password     :string
#  reset_password_token   :string
#  reset_password_sent_at :datetime
#  remember_created_at    :datetime
#  nickname               :string
#  phone                  :string
#  date_of_birth          :date
#  sex                    :integer
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  timezone               :string           default("Asia/Hong_Kong"), not null
#  whats_app_number       :string
#  banbie                 :string
#  class_no               :string
#  failed_attempts        :integer          default(0)
#  unlock_token           :string
#  locked_at              :datetime
#  meta                   :jsonb            not null
#  konnecai_tokens        :jsonb            not null
#
# Indexes
#
#  index_general_users_on_email  (email) UNIQUE
#
require_dependency 'has_kg_linker'

class GeneralUser < ApplicationRecord
  self.primary_key = 'id'

  VALID_AI_ENGLISH_FEATURES = %w[essay comprehension speaking_essay speaking_conversation sentence_builder
                                 speaking_pronunciation].freeze

  validate :aienglish_features_must_be_valid

  store_accessor :konnecai_tokens, :essay, :comprehension, :speaking_essay, :speaking_conversation, :sentence_builder,
                 :speaking_pronunciation

  # has_and_belongs_to_many :roles, join_table: :users_roles

  devise :database_authenticatable,
         :jwt_authenticatable,
         :registerable,
         :recoverable,
         :rememberable,
         :validatable,
         :lockable,
         jwt_revocation_strategy: JwtDenylist

  has_one :energy, as: :user, dependent: :destroy
  has_many :purchases, as: :user, dependent: :destroy
  has_many :purchased_marketplace_items, through: :purchases, source: :marketplace_item
  has_many :user_marketplace_items, dependent: :destroy, as: :user, class_name: 'UserMarketplaceItem'
  has_many :marketplace_items, through: :user_marketplace_items
  has_many :general_user_files, dependent: :destroy
  has_many :general_user_feeds, dependent: :destroy

  has_many :assessment_records, as: :recordable
  has_many :scheduled_tasks, as: :user, dependent: :destroy

  has_many :memberships, dependent: :destroy
  has_many :groups, through: :memberships

  has_many :essay_gradings
  has_many :essay_assignments

  has_many :student_enrollments, dependent: :destroy
  has_many :school_academic_years, through: :student_enrollments

  # 直接關聯到學校，這是可選的，用於學校直接指派的用戶
  belongs_to :school, optional: true

  # 添加教師任教記錄關聯
  has_many :teacher_assignments, dependent: :destroy
  has_many :teaching_academic_years, through: :teacher_assignments, source: :school_academic_year

  scope :search_query, lambda { |query|
    return nil if query.blank?

    terms = query.to_s.downcase.split(/\s+/)
    terms = terms.map do |e|
      "%#{"#{e.gsub('*', '%')}%".gsub(/%+/, '%')}"
    end
    num_or_conditions = 2
    where(
      terms.map do
        or_clauses = [
          'LOWER(nickname) LIKE ?',
          'LOWER(email) LIKE ?'
        ].join(' OR ')
        "(#{or_clauses})"
      end.join(' AND '),
      *terms.map { |e| [e] * num_or_conditions }.flatten
    )
  }

  # include HasKgLinker

  def jwt_payload
    {
      'sub' => id,
      'iat' => Time.now.to_i,
      'email' => email
    }
  end

  def consume_energy(marketplace_item_id, energy_cost)
    # Run the energy consumption
    if energy.value >= energy_cost
      energy.update(value: energy.value - energy_cost)
      # Create energy consumption record
      EnergyConsumptionRecord.create!(
        user: self,
        marketplace_item_id:,
        energy_consumed: energy_cost
      )
      true
    else
      false
    end
  end

  def chatbots
    # 创建一个空数组来保存提取的信息
    chatbot_details = []

    # 遍历原始数组，提取每个 market_item 下的 chatbot 信息
    purchased_items.each do |item|
      next unless item['marketplace_item']

      chatbot_info = item['marketplace_item']
      chatbot_details << {
        chatbot_id: chatbot_info['chatbot_id'],
        chatbot_name: chatbot_info['chatbot_name'],
        chatbot_description: chatbot_info['chatbot_description']
      }
    end

    chatbot_details.uniq
  end

  def check_can_consume_energy(_chatbot, energy_cost)
    energy.value >= energy_cost
  end

  def purchased_items
    purchases.includes(:marketplace_item).as_json(include: :marketplace_item)
  end

  # 以下方法應該是放入去 concern 的，但係唔知點解冇效，所以搬返出黎就算
  def method_missing(method_name, *arguments, &block)
    if method_name.to_s.start_with?('linked_')
      relation_name = method_name.to_s.sub('linked_', '')
      singular_relation_name = relation_name.to_s.singularize

      # 调用动态处理关系的私有方法
      return linkable_relation(singular_relation_name) if respond_to_relation?(relation_name)
    end

    super
  end

  def respond_to_missing?(method_name, include_private = false)
    if method_name.to_s.start_with?('linked_')
      relation_name = method_name.to_s.sub('linked_', '')
      return respond_to_relation?(relation_name)
    end

    super
  end

  def linkable_relation(relation_name)
    # 查询符合条件的KgLinker记录
    linkers = KgLinker.where(map_from: self, relation: "has_#{relation_name}")

    # 假設左 link 出來的 object 是同一個 type
    return [] if linkers.empty?

    map_to_class = linkers.first.map_to_type.constantize
    map_to_class.where(id: linkers.pluck(:map_to_id))
  end

  def respond_to_relation?(_relation_name)
    # 假设总是返回true，或者你需要一些逻辑来验证这个关系是否有效
    true
  end

  def find_teachers_via_students
    teacher_ids = KgLinker.where(map_to_id: id, relation: 'has_student')
                          .pluck(:map_from_id)
                          .uniq
    GeneralUser.where(id: teacher_ids).order(created_at: :desc).as_json(except: %i[aienglish_feature_list])
  end

  def show_in_report_name
    "#{email} (#{nickname}, #{banbie}, #{class_no})"
  end

  # AI English features getter, setter and validator section (aienglish_role, aienglish_features_list, aienglish_user?)
  def aienglish_role
    meta['aienglish_role']
  end

  def aienglish_role=(value)
    meta['aienglish_role'] = value
    save
  end

  def aienglish_features_list
    meta['aienglish_features_list'] || []
  end

  def aienglish_features_list=(features)
    meta['aienglish_features_list'] = features
    save
  end

  # 確認是否具備AI English功能
  def aienglish_user?
    meta['aienglish_role'].present? && meta['aienglish_features_list'].present?
  end

  # 獲取指定日期的班級信息
  def enrollment_at(date)
    student_enrollments.at_date(date).first
  end

  # 獲取當前班級信息
  def current_enrollment
    student_enrollments
      .joins(:school_academic_year)
      .where('school_academic_years.status = ?', SchoolAcademicYear.statuses[:active])
      .first
  end

  # 獲取當前任教記錄
  def current_teaching_assignment
    teacher_assignments
      .joins(:school_academic_year)
      .where('school_academic_years.status = ?', SchoolAcademicYear.statuses[:active])
      .first
  end

  # 判斷是否為特定學校的教師
  # @param school [School] 要檢查的學校
  # @param date [Date, nil] 可選的日期參數，用於檢查特定日期的教師狀態
  # @return [Boolean] 是否為該學校的教師
  def teacher_at?(school, date = nil)
    # 基本參數驗證
    return false unless school.is_a?(School)

    # 構建基礎查詢
    query = teacher_assignments
            .joins(:school_academic_year)
            .where(school_academic_years: { school_id: school.id })

    # 如果提供了日期，使用該日期進行過濾
    if date.present?
      query = query.where('school_academic_years.start_date <= ? AND school_academic_years.end_date >= ?', date, date)
    end

    # 只檢查有效的學年
    query = query.where('school_academic_years.status = ?', SchoolAcademicYear.statuses[:active])

    # 只檢查在職的教師
    query = query.where(status: TeacherAssignment.statuses[:active])

    # 執行查詢並返回結果
    query.exists?
  end

  # 獲取在特定學校的教師職位信息
  # @param school [School] 要查詢的學校
  # @param date [Date, nil] 可選的日期參數
  # @return [Array<Hash>] 教師職位信息列表
  def teaching_positions_at(school, date = nil)
    return [] unless teacher_at?(school, date)

    query = teacher_assignments
            .joins(:school_academic_year)
            .where(school_academic_years: { school_id: school.id })
            .where(status: TeacherAssignment.statuses[:active])

    if date.present?
      query = query.where('school_academic_years.start_date <= ? AND school_academic_years.end_date >= ?', date, date)
    end

    query.map do |assignment|
      {
        department: assignment.department,
        position: assignment.position,
        teaching_subjects: assignment.meta['teaching_subjects'] || [],
        class_teacher_of: assignment.meta['class_teacher_of'],
        additional_duties: assignment.meta['additional_duties'] || [],
        start_date: assignment.school_academic_year.start_date,
        end_date: assignment.school_academic_year.end_date
      }
    end
  end

  # 檢查是否為特定學校特定部門的教師
  # @param school [School] 要檢查的學校
  # @param department [String] 部門名稱
  # @param date [Date, nil] 可選的日期參數
  # @return [Boolean] 是否為該部門的教師
  def teacher_in_department?(school, department, date = nil)
    return false unless teacher_at?(school, date)

    query = teacher_assignments
            .joins(:school_academic_year)
            .where(school_academic_years: { school_id: school.id })
            .where(department:)
            .where(status: TeacherAssignment.statuses[:active])

    if date.present?
      query = query.where('school_academic_years.start_date <= ? AND school_academic_years.end_date >= ?', date, date)
    end

    query.exists?
  end

  def set_konnecai_tokens_all_same(web_token)
    # 定義 category 的鍵
    categories = %w[essay comprehension speaking_conversation speaking_essay sentence_builder speaking_pronunciation]

    # 遍歷 categories 的每個鍵，將其值設置為 web_token
    categories.each do |category|
      konnecai_tokens[category] = web_token
    end

    # 保存更改
    save
  end

  # 添加一個方法來獲取學校，無論用戶是學生還是教師
  # 只允許 AI English 用戶使用
  def get_school
    # 首先檢查是否為 AI English 用戶
    return nil unless aienglish_user?

    # 如果用戶直接關聯到學校
    return school if school.present?

    # 如果是學生，通過enrollment獲取學校
    if aienglish_role != 'teacher' && current_enrollment.present?
      return current_enrollment.school_academic_year.school
    # 如果是教師，通過teaching assignment獲取學校
    elsif aienglish_role == 'teacher' && current_teaching_assignment.present?
      return current_teaching_assignment.school_academic_year.school
    end

    # 如果沒有找到學校關聯，返回nil
    nil
  end

  # 獲取學校Logo URL的方法
  # 只允許 AI English 用戶使用
  def school_logo_url(size = :small)
    # 首先檢查是否為 AI English 用戶
    return nil unless aienglish_user?

    school = get_school
    return nil unless school&.logo&.attached?

    case size
    when :thumbnail
      school.logo_thumbnail_url
    when :small
      school.logo_small_url
    when :large
      school.logo_large_url
    when :square
      school.logo_square_url
    else
      school.logo_url
    end
  end

  private

  def aienglish_features_must_be_valid
    # 確保 features list 存在於 meta 並且是合法的
    invalid_features = aienglish_features_list - VALID_AI_ENGLISH_FEATURES
    return if invalid_features.empty?

    errors.add(:aienglish_features, "Can only include allowed features: #{invalid_features.join(', ')}")
  end
end
