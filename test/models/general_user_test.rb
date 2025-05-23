# frozen_string_literal: true

# == Schema Information
#
# Table name: public.general_users
#
#  id                     :uuid             not null, primary key
#  email                  :string
#  encrypted_password     :string
#  reset_password_token   :string
#  reset_password_sent_at :datetime
#  remember_created_at    :datetime
#  nickname               :string
#  phone                  :string
#  date_of_birth          :date
#  sex                    :integer
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  timezone               :string           default("Asia/Hong_Kong"), not null
#  whats_app_number       :string
#  banbie                 :string
#  class_no               :string
#  failed_attempts        :integer          default(0)
#  unlock_token           :string
#  locked_at              :datetime
#  meta                   :jsonb            not null
#  konnecai_tokens        :jsonb            not null
#
# Indexes
#
#  index_general_users_on_email  (email) UNIQUE
#
require 'test_helper'

class GeneralUserTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
