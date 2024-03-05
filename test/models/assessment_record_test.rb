# frozen_string_literal: true

# == Schema Information
#
# Table name: assessment_records
#
#  id              :uuid             not null, primary key
#  title           :string
#  record          :jsonb
#  meta            :jsonb
#  recordable_type :string
#  recordable_id   :uuid
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#
# Indexes
#
#  index_assessment_records_on_recordable  (recordable_type,recordable_id)
#
require 'test_helper'

class AssessmentRecordTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
