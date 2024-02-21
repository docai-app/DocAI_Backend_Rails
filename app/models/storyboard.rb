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
# Indexes
#
#  index_storyboards_on_user_id  (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class Storyboard < ApplicationRecord
  has_many :storyboard_item_associations, dependent: :destroy
  has_many :items, through: :storyboard_item_associations, source: :storyboard_item
  belongs_to :user
end
