# frozen_string_literal: true

# == Schema Information
#
# Table name: general_user_feeds
#
#  id                       :uuid             not null, primary key
#  general_user_id          :uuid             not null
#  title                    :string           default("")
#  description              :string           default("")
#  cover_image              :string           default("")
#  file_type                :string           not null
#  file_url                 :string           default("")
#  file_size                :integer          default(0)
#  user_marketplace_item_id :uuid
#  meta                     :jsonb
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  file_content             :text
#
# Indexes
#
#  index_general_user_feeds_on_file_type                 (file_type)
#  index_general_user_feeds_on_file_type                 (file_type)
#  index_general_user_feeds_on_general_user_id           (general_user_id)
#  index_general_user_feeds_on_general_user_id           (general_user_id)
#  index_general_user_feeds_on_user_marketplace_item_id  (user_marketplace_item_id)
#  index_general_user_feeds_on_user_marketplace_item_id  (user_marketplace_item_id)
#
# Foreign Keys
#
#  fk_rails_...  (general_user_id => general_users.id)
#  fk_rails_...  (general_user_id => public.general_users.id)
#  fk_rails_...  (user_marketplace_item_id => user_marketplace_items.id)
#  fk_rails_...  (user_marketplace_item_id => public.user_marketplace_items.id)
#
class GeneralUserFeed < ApplicationRecord
  belongs_to :general_user
  belongs_to :user_marketplace_item

  # validates :file_url, presence: true

  def self.ransackable_attributes(_auth_object = nil)
    %w[file_type]
  end
end
