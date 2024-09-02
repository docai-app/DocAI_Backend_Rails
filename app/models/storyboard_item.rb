# frozen_string_literal: true

# == Schema Information
#
# Table name: storyboard_items
#
#  id          :uuid             not null, primary key
#  name        :string           not null
#  description :text
#  user_id     :uuid             not null
#  query       :string           not null
#  data        :text             default("")
#  sql         :text             default("")
#  meta        :jsonb
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  is_ready    :boolean          default(FALSE), not null
#  status      :integer          default("cached"), not null
#  object_type :string           not null
#  object_id   :uuid             not null
#  item_type   :string
#
# Indexes
#
#  index_storyboard_items_on_user_id  (user_id)
#  index_storyboard_items_on_user_id  (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => public.users.id)
#  fk_rails_...  (user_id => users.id)
#
class StoryboardItem < ApplicationRecord
  has_many :storyboard_item_associations, dependent: :destroy
  has_many :storyboards, through: :storyboard_item_associations
  belongs_to :object, polymorphic: true, optional: true, dependent: :destroy

  enum status: %i[cached saved]
end
