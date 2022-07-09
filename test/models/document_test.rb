# == Schema Information
#
# Table name: documents
#
#  id               :uuid             not null, primary key
#  name             :string
#  storage_url      :string
#  content          :text
#  status           :integer          default("pending"), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  approval_status  :integer          default("awaiting"), not null
#  approval_user_id :uuid
#  approval_at      :datetime
#
require "test_helper"

class DocumentTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
