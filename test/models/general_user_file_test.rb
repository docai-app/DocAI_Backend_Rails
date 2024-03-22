# frozen_string_literal: true

# == Schema Information
#
# Table name: public.general_user_files
#
#  id                       :uuid             not null, primary key
#  general_user_id          :uuid             not null
#  file_type                :string           not null
#  file_url                 :string
#  file_size                :integer          default(0), not null
#  title                    :string           default("")
#  user_marketplace_item_id :uuid
#  meta                     :jsonb
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#
# Indexes
#
#  index_general_user_files_on_file_type                 (file_type)
#  index_general_user_files_on_general_user_id           (general_user_id)
#  index_general_user_files_on_user_marketplace_item_id  (user_marketplace_item_id)
#
# Foreign Keys
#
#  fk_rails_...  (general_user_id => general_users.id)
#  fk_rails_...  (user_marketplace_item_id => user_marketplace_items.id)
#
require 'test_helper'

class GeneralUserFileTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
