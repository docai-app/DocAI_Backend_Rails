# frozen_string_literal: true

# == Schema Information
#
# Table name: storyboards
#
#  id          :uuid             not null, primary key
#  title       :string           not null
#  description :text
#  user_id     :uuid             not null
#  meta        :jsonb
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
class Storyboard < ApplicationRecord
  has_many :storyboard_item_associations, dependent: :destroy
  has_many :items, through: :storyboard_item_associations, source: :storyboard_item
  belongs_to :user
end
