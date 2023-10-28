# frozen_string_literal: true

# == Schema Information
#
# Table name: functions
#
#  id          :uuid             not null, primary key
#  name        :string
#  description :string
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  title       :string           default(""), not null
#
class Function < ApplicationRecord
  has_many :tag_functions, dependent: :destroy
  has_one :tag_function, dependent: :destroy, class_name: 'TagFunction', foreign_key: 'function_id'
  has_one :tag, through: :tag_functions, class_name: 'Tag', foreign_key: 'tag_id'
end
