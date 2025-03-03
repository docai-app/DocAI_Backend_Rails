class StudentSnapshot < ApplicationRecord
  belongs_to :general_user
  has_many :essay_gradings

  # 驗證必填欄位
  validates :nickname, :class_name, :class_no, :academic_year, :semester, presence: true

  # 創建快照的工廠方法
  def self.create_from_user(user, academic_year, semester)
    create(
      general_user_id: user.id,
      nickname: user.nickname,
      class_name: user.banbie,
      class_no: user.class_no,
      school_id: user.school_id,
      academic_year:,
      semester:
    )
  end
end
