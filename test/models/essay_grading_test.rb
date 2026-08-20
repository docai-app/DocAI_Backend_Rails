# frozen_string_literal: true

# == Schema Information
#
# Table name: public.essay_gradings
#
#  id                          :uuid             not null, primary key
#  essay                       :text
#  topic                       :string
#  status                      :integer          default("pending"), not null
#  grading                     :jsonb            not null
#  general_user_id             :uuid             not null
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  essay_assignment_id         :uuid
#  general_context             :jsonb            not null
#  using_time                  :integer          default(0), not null
#  meta                        :jsonb            not null
#  score                       :decimal(, )
#  sentence_builder            :jsonb
#  submission_class_name       :string
#  submission_class_number     :string
#  submission_school_id        :uuid
#  submission_academic_year_id :uuid
#
# Indexes
#
#  index_essay_gradings_on_essay_assignment_id  (essay_assignment_id)
#
# Foreign Keys
#
#  fk_rails_...  (essay_assignment_id => essay_assignments.id)
#  fk_rails_...  (general_user_id => general_users.id)
#
require 'test_helper'

class EssayGradingTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  test 'submission snapshot uses the academic year enrollment class number' do
    school = Struct.new(:id).new(SecureRandom.uuid)
    academic_year = Struct.new(:id, :school_id).new(SecureRandom.uuid, school.id)
    enrollment = Struct.new(:id, :class_name, :class_number, :school_academic_year)
                       .new('enrollment-1', 'F2A', '18', academic_year)
    user = Struct.new(:id, :banbie, :class_no, :current_enrollment)
                 .new('student-1', 'F3A', '99', enrollment)
    grading = EssayGrading.new
    grading.define_singleton_method(:general_user) { user }

    grading.send(:save_submission_info)

    assert_equal 'F2A', grading.submission_class_name
    assert_equal '18', grading.submission_class_number
    assert_equal school.id, grading.submission_school_id
    assert_equal academic_year.id, grading.submission_academic_year_id
  end
end
