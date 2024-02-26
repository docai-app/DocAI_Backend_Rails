# frozen_string_literal: true

# == Schema Information
#
# Table name: messages
#
#  id                       :uuid             not null, primary key
#  chatbot_id               :uuid             not null
#  content                  :text             not null
#  role                     :string           default("user"), not null
#  user_id                  :uuid
#  object_type              :string           not null
#  is_read                  :boolean          default(FALSE), not null
#  meta                     :jsonb
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  user_marketplace_item_id :uuid
#
# Indexes
#
#  index_messages_on_chatbot_id                (chatbot_id)
#  index_messages_on_object_type               (object_type)
#  index_messages_on_user_id                   (user_id)
#  index_messages_on_user_marketplace_item_id  (user_marketplace_item_id)
#
# Foreign Keys
#
#  fk_rails_...  (chatbot_id => chatbots.id)
#  fk_rails_...  (user_id => users.id)
#  fk_rails_...  (user_marketplace_item_id => user_marketplace_items.id)
#
class Message < ApplicationRecord
  has_paper_trail

  store_accessor :meta, :belongs_user_id
  belongs_to :chatbot, class_name: 'Chatbot', foreign_key: 'chatbot_id', optional: true, dependent: :destroy
  belongs_to :user_marketplace_item, optional: true, dependent: :destroy, foreign_key: 'user_marketplace_item_id'
end
