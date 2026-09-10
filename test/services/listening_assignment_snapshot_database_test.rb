# frozen_string_literal: true

# Explicitly isolated Postgres test, no Rails initializers or production config.
require 'logger'
require 'active_record'
require 'minitest/autorun'
require 'minitest/mock'
require_relative '../../app/models/application_record'
require_relative '../../app/services/listening_snapshot_scorer'
require_relative '../../app/models/listening_assignment_snapshot'
require_relative '../../app/services/listening_qg_version_client'
require_relative '../../app/services/listening_assignment_creator'
require_relative '../../app/models/concerns/trusted_listening_grading'
require_relative '../../app/models/concerns/listening_assignment_version_guard'
require_relative '../../db/migrate/20260909120000_create_listening_assignment_snapshots'

raise 'Set LISTENING_SNAPSHOT_ISOLATED_TEST=1' unless ENV['LISTENING_SNAPSHOT_ISOLATED_TEST'] == '1'
ActiveRecord::Base.establish_connection(adapter: 'postgresql', host: '127.0.0.1', port: 55439,
  database: 'listening_assignment_isolated_test', username: 'listening_test', password: 'listening-local-only')
connection = ActiveRecord::Base.connection
raise 'Wrong test database' unless connection.select_value('SELECT current_database()') == 'listening_assignment_isolated_test'
unless connection.table_exists?(:essay_assignments)
  connection.create_table(:essay_assignments, id: :uuid) { |t| t.string :category }
end
CreateListeningAssignmentSnapshots.new.migrate(:up) unless connection.table_exists?(:listening_assignment_snapshots)
connection.add_column(:essay_assignments, :meta, :jsonb, default: {}) unless connection.column_exists?(:essay_assignments, :meta)
unless connection.table_exists?(:essay_gradings)
  connection.create_table(:essay_gradings, id: :uuid) do |t|
    t.uuid :essay_assignment_id
    t.jsonb :grading, default: {}
    t.string :status, default: 'pending'
    t.decimal :score
  end
end

# Minimal owner model keeps these persistence tests independent of unrelated
# production callbacks. Full controller/assignment integration is separate.
class EssayAssignment < ApplicationRecord
  include ListeningAssignmentVersionGuard
  has_one :listening_assignment_snapshot
end

class EssayGrading < ApplicationRecord
  include TrustedListeningGrading
  belongs_to :essay_assignment
  def is_listening?
    essay_assignment&.category == 'listening'
  end
end

class ListeningAssignmentSnapshotDatabaseTest < Minitest::Test
  def setup
    ActiveRecord::Base.connection.begin_transaction(joinable: false)
    @owner = EssayAssignment.create!(id: SecureRandom.uuid, category: 'listening')
    @quiz = { 'level' => 'A2', 'title' => 'Library', 'instruction' => 'Listen.', 'full_score' => 4,
      'questions' => { 'fill_in_the_blanks' => [], 'multiple_choice' => Array.new(4) { |i|
        { 'id' => i + 1, 'type' => 'multiple_choice', 'question' => 'Which day?', 'answer' => 'A',
          'evidence' => ['PRIVATE'], 'options' => { 'A' => 'One', 'B' => 'Two', 'C' => 'Three', 'D' => 'Four' } }
      } } }
    @attributes = { essay_assignment: @owner, qg_version_id: '123', content_digest: 'a' * 64,
      level: 'A2', quiz: @quiz, plain_transcript: 'PRIVATE', audio_url: 'https://storage.example/audio.wav',
      audio_metadata: { 'sha256' => 'b' * 64 } }
  end

  def teardown
    ActiveRecord::Base.connection.rollback_transaction
  end

  def test_private_copy_persists_and_student_projection_has_no_secrets
    snapshot = ListeningAssignmentSnapshot.create!(@attributes).reload
    assert_equal 1, snapshot.score([{ 'id' => 1, 'user_answer' => 'A' }])['score']
    public_content = snapshot.student_content
    refute_includes public_content.to_json, 'PRIVATE'
    refute_includes public_content.to_json, 'storage.example'
    assert_equal %w[id options question type], public_content['questions'][0].keys.sort
    refute_includes @owner.as_json.keys, 'listening_assignment_snapshot'
    public_content['questions'][0]['options']['A'] = 'changed'
    assert_equal 'One', snapshot.quiz['questions']['multiple_choice'][0]['options']['A']
  end

  def test_persisted_content_and_owner_cannot_be_changed
    snapshot = ListeningAssignmentSnapshot.create!(@attributes)
    refute snapshot.update(plain_transcript: 'replacement')
    assert_equal 'PRIVATE', snapshot.reload.plain_transcript
    refute snapshot.update(qg_version_id: '456')
    assert_equal '123', snapshot.reload.qg_version_id
  end

  def test_assignment_has_exactly_one_snapshot
    ListeningAssignmentSnapshot.create!(@attributes)
    assert_raises(ActiveRecord::RecordInvalid) { ListeningAssignmentSnapshot.create!(@attributes) }
    duplicate = ListeningAssignmentSnapshot.new(@attributes)
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
  end

  def test_invalid_quiz_wrong_category_or_ephemeral_url_rejected
    refute ListeningAssignmentSnapshot.new(@attributes.merge(level: 'C2')).valid?
    refute ListeningAssignmentSnapshot.new(@attributes.merge(audio_url: 'https://storage.example/a?sig=temporary')).valid?
    @owner.update!(category: 'essay')
    refute ListeningAssignmentSnapshot.new(@attributes).valid?
  end

  def new_assignment
    EssayAssignment.new(id: SecureRandom.uuid, category: 'listening', meta: {
      'listening_transcript' => 'FORGED', 'listening' => {
        'version_id' => '123', 'news_feed_id' => '34', 'level' => 'A2',
        'play_limit' => 2, 'questions' => ['FORGED'], 'audio_url' => 'FORGED'
      }
    })
  end

  def test_creator_saves_both_and_removes_client_private_content
    assignment = new_assignment
    client = Minitest::Mock.new
    client.expect(:fetch, @attributes.except(:essay_assignment), version_id: '123', news_feed_id: '34', level: 'A2')
    assert ListeningAssignmentCreator.call(assignment: assignment, client: client)
    client.verify
    assert assignment.reload.listening_assignment_snapshot
    refute_includes assignment.meta.to_json, 'FORGED'
    assert_equal 2, assignment.meta['listening']['play_limit']
  end

  def test_creator_rolls_back_assignment_when_snapshot_fails
    assignment = new_assignment
    before = EssayAssignment.count
    client = Minitest::Mock.new
    client.expect(:fetch, @attributes.except(:essay_assignment).merge(content_digest: 'invalid'),
      version_id: '123', news_feed_id: '34', level: 'A2')
    refute ListeningAssignmentCreator.call(assignment: assignment, client: client)
    assert_equal before, EssayAssignment.count
    refute EssayAssignment.exists?(assignment.id)
  end

  def test_submission_uses_snapshot_and_draft_does_not_reveal_correctness
    ListeningAssignmentSnapshot.create!(@attributes)
    submission = EssayGrading.create!(id: SecureRandom.uuid, essay_assignment: @owner, status: 'draft',
      grading: { 'listening' => { 'score' => 999, 'questions' => [
        { 'id' => 1, 'user_answer' => 'B', 'answer' => 'B', 'is_correct' => true }
      ] } })
    submission.reload
    assert_nil submission.score
    assert_equal %w[id user_answer], submission.grading['listening']['questions'][0].keys.sort
    refute submission.grading['listening'].key?('percentage')
    submission.update!(status: 'pending')
    assert_equal 'graded', submission.reload.status
    assert_equal 0, submission.score
    assert_equal false, submission.grading['listening']['questions'][0]['is_correct']
  end

  def test_missing_snapshot_and_invalid_responses_cannot_be_saved
    submission = EssayGrading.new(id: SecureRandom.uuid, essay_assignment: @owner, grading: {})
    refute submission.save
    ListeningAssignmentSnapshot.create!(@attributes)
    @owner.reload
    submission.grading = { 'listening' => { 'questions' => [{ 'id' => 999, 'user_answer' => 'A' }] } }
    refute submission.save
    refute EssayGrading.exists?(submission.id)
  end

  def test_snapshot_assignment_cannot_change_category_or_metadata
    ListeningAssignmentSnapshot.create!(@attributes)
    refute @owner.update(category: 'essay')
    assert_equal 'listening', @owner.reload.category
    refute @owner.update(meta: { 'listening' => { 'level' => 'C2' } })
    assert_equal({}, @owner.reload.meta)
    assert @owner.save
  end
end
