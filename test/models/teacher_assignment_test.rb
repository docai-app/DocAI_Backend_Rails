# frozen_string_literal: true

# == Schema Information
#
# Table name: teacher_assignments
#
#  id                      :uuid             not null, primary key
#  general_user_id         :uuid             not null
#  school_academic_year_id :uuid             not null
#  department              :string
#  position                :string
#  status                  :integer
#  meta                    :jsonb            not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#
# Indexes
#
#  index_teacher_assignments_on_general_user_id          (general_user_id)
#  index_teacher_assignments_on_school_academic_year_id  (school_academic_year_id)
#
# Foreign Keys
#
#  fk_rails_...  (general_user_id => general_users.id)
#  fk_rails_...  (school_academic_year_id => school_academic_years.id)
#
require 'test_helper'

class TeacherAssignmentTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
