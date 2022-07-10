# == Schema Information
#
# Table name: document_approvals
#
#  id               :uuid             not null, primary key
#  document_id      :uuid
#  form_data_id     :uuid
#  approval_user_id :uuid
#  approval_status  :integer          default(0), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#
require "test_helper"

class DocumentApprovalTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
