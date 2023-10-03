# frozen_string_literal: true

# == Schema Information
#
# Table name: chatbots
#
#  id           :uuid             not null, primary key
#  name         :string
#  description  :string
#  user_id      :uuid             not null
#  category     :integer          default("assistant"), not null
#  meta         :jsonb
#  source       :jsonb
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  is_public    :boolean          default(FALSE), not null
#  expired_at   :datetime
#  access_count :integer          default(0)
#
class Chatbot < ApplicationRecord
  enum category: %i[assistant]

  belongs_to :user, optional: true, class_name: 'User', foreign_key: 'user_id'

  def increment_access_count!
    increment(:access_count).save
  end

  def has_expired?
    expired_at.present? && Time.current > expired_at
  end
end
