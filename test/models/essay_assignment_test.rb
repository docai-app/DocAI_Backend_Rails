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
  def build_speaking_pronunciation_assignment(meta_overrides = {})
    EssayAssignment.new(
      general_user: general_users(:one),
      category: :speaking_pronunciation,
      assignment: 'S5 Essay',
      topic: 'Pronunciation Drill',
      rubric: {},
      meta: {
        'speaking_pronunciation_pass_score' => 60,
        'speaking_pronunciation_sentences' => [{ 'sentence' => 'Hello world' }]
      }.deep_merge(meta_overrides)
    )
  end

  test 'requires at least one pronunciation sentence' do
    assignment = build_speaking_pronunciation_assignment(
      'speaking_pronunciation_sentences' => []
    )

    assert_not assignment.valid?
    assert_includes assignment.errors[:base], 'Please add pronunciation sentences before saving.'
  end

  test 'requires every pronunciation sentence to be completed' do
    assignment = build_speaking_pronunciation_assignment(
      'speaking_pronunciation_sentences' => [
        { 'sentence' => 'Hello world' },
        { 'sentence' => '   ' }
      ]
    )

    assert_not assignment.valid?
    assert_includes assignment.errors[:base], 'Please complete every pronunciation sentence before saving.'
  end

  test 'enriches pronunciation sentences with ipa after save' do
    raw_sentences = [{ 'sentence' => 'Hello world' }]
    enriched_sentences = [{ 'sentence' => 'Hello world', 'ipa_transcript' => 'həˈloʊ wɝːld' }]
    fake_transcriber = Minitest::Mock.new
    fake_transcriber.expect(:enrich_sentences, enriched_sentences, [raw_sentences])

    PronunciationIpaTranscriberService.stub(:new, fake_transcriber) do
      assignment = build_speaking_pronunciation_assignment(
        'speaking_pronunciation_sentences' => raw_sentences
      )

      assignment.save!

      assert_equal enriched_sentences, assignment.reload.meta['speaking_pronunciation_sentences']
    end

    fake_transcriber.verify
  end
end
