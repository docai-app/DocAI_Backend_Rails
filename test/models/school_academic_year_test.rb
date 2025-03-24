# frozen_string_literal: true

# == Schema Information
#
# Table name: school_academic_years
#
#  id         :uuid             not null, primary key
#  school_id  :uuid             not null
#  name       :string           not null
#  start_date :date             not null
#  end_date   :date             not null
#  status     :integer          default("preparing")
#  meta       :jsonb            not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_school_academic_years_on_school_id  (school_id)
#
# Foreign Keys
#
#  fk_rails_...  (school_id => schools.id)
#
require 'test_helper'

class SchoolAcademicYearTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
