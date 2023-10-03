# frozen_string_literal: true

# == Schema Information
#
# Table name: mini_apps
#
#  id          :uuid             not null, primary key
#  name        :string
#  description :string
#  meta        :jsonb
#  user_id     :uuid             not null
#  folder_id   :uuid
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
require 'test_helper'

class MiniAppTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
