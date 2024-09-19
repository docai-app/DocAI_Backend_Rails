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
# Indexes
#
#  index_user_mailboxes_on_document_id  (document_id)
#  index_user_mailboxes_on_document_id  (document_id)
#  index_user_mailboxes_on_user_id      (user_id)
#  index_user_mailboxes_on_user_id      (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (document_id => documents.id)
#  fk_rails_...  (document_id => public.documents.id)
#  fk_rails_...  (user_id => users.id)
#  fk_rails_...  (user_id => public.users.id)
#
require 'test_helper'

class UserMailboxTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
