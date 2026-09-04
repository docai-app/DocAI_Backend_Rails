# frozen_string_literal: true

# == Schema Information
#
# Table name: public.essay_assignments
#
#  id                   :uuid             not null, primary key
#  topic                :string
#  rubric               :jsonb            not null
#  code                 :string           not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  assignment           :string
#  number_of_submission :integer          default(0), not null
#  general_user_id      :uuid
#  category             :integer          default("essay"), not null
#  title                :string
#  hints                :string
#  meta                 :jsonb            not null
#  answer_visible       :boolean          default(TRUE), not null
#  remark               :string
#
# Indexes
#
#  index_essay_assignments_on_category         (category)
#  index_essay_assignments_on_code             (code) UNIQUE
#  index_essay_assignments_on_general_user_id  (general_user_id)
#
require 'test_helper'

class EssayAssignmentTest < ActiveSupport::TestCase
  test 'talk lab speaking defaults to fixed app keys' do
    old_grading = ENV['TALK_LAB_SPEAKING_GRADING_APP_KEY']
    old_general_context = ENV['TALK_LAB_SPEAKING_GENERAL_CONTEXT_APP_KEY']
    ENV['TALK_LAB_SPEAKING_GRADING_APP_KEY'] = 'talk-lab-grading-key'
    ENV['TALK_LAB_SPEAKING_GENERAL_CONTEXT_APP_KEY'] = 'talk-lab-context-key'

    assignment = EssayAssignment.new(
      general_user: general_users(:one),
      category: 'talk_lab_speaking',
      topic: 'Travel',
      title: 'Travel Talk Lab',
      assignment: 'Talk about a trip.',
      rubric: {}
    )

    assert assignment.valid?
    assert_equal 'Talk Lab Speaking', assignment.rubric['name']
    assert_equal 'talk-lab-grading-key', assignment.rubric.dig('app_key', 'grading')
    assert_equal 'talk-lab-context-key', assignment.rubric.dig('app_key', 'general_context')
  ensure
    ENV['TALK_LAB_SPEAKING_GRADING_APP_KEY'] = old_grading
    ENV['TALK_LAB_SPEAKING_GENERAL_CONTEXT_APP_KEY'] = old_general_context
  end

  test 'talk lab speaking meta is filtered from list response' do
    filtered = EssayAssignment.meta_for_list_response(
      {
        'talk_lab_speaking' => { 'rtc_prompt_materials' => { 'large' => true } },
        'level' => 'CEFR B2'
      },
      category: 'talk_lab_speaking'
    )

    assert_equal({ 'level' => 'CEFR B2' }, filtered)
  end
end
