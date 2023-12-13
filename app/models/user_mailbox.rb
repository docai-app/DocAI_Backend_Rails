# frozen_string_literal: true

# == Schema Information
#
# Table name: user_mailboxes
#
#  id          :uuid             not null, primary key
#  user_id     :uuid             not null
#  document_id :uuid             not null
#  message_id  :string
#  subject     :string
#  sender      :string
#  recipient   :string
#  sent_at     :datetime
#  received_at :datetime
#  attachment  :jsonb
#  content     :text
#  read        :boolean          default(FALSE)
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
class UserMailbox < ApplicationRecord
  belongs_to :user
  belongs_to :document
end
