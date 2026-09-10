# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../app/services/listening_snapshot_scorer'

class ListeningSnapshotScorerStandaloneTest < Minitest::Test
  def quiz(level = 'A2')
    count = ListeningSnapshotScorer::COUNTS.fetch(level)
    { 'level' => level, 'full_score' => count, 'questions' => {
      'fill_in_the_blanks' => [], 'multiple_choice' => Array.new(count) { |i|
        { 'id' => i + 1, 'type' => 'multiple_choice', 'answer' => %w[A B C D][i % 4],
          'options' => { 'A' => 'One', 'B' => 'Two', 'C' => 'Three', 'D' => 'Four' } }
      }
    } }
  end

  def score(responses, snapshot = quiz)
    ListeningSnapshotScorer.call(quiz: snapshot, responses: responses)
  end

  def test_all_levels_score_from_snapshot
    %w[A2 B2 C2].each do |level|
      snapshot = quiz(level)
      responses = snapshot['questions']['multiple_choice'].reverse.map { |q| { 'id' => q['id'].to_s, 'user_answer' => q['answer'] } }
      result = score(responses, snapshot)
      assert_equal snapshot['full_score'], result['score']
      assert_equal 100, result['percentage']
    end
  end

  def test_forged_answers_points_and_metadata_are_not_used_or_returned
    result = score([{ 'id' => 1, 'user_answer' => 'B', 'answer' => 'B', 'score' => 999,
      'full_score' => 999, 'is_correct' => true, 'options' => { 'B' => 'One' } }])
    assert_equal 0, result['score']
    assert_equal 4, result['full_score']
    assert_equal %w[id is_correct score user_answer], result['questions'].first.keys.sort
  end

  def test_omissions_and_blank_answers_count_as_wrong
    assert_equal 0, score([])['percentage']
    assert_equal 25, score([{ 'id' => 1, 'user_answer' => 'A' }, { 'id' => 2, 'user_answer' => '' }])['percentage']
  end

  def test_rejects_unknown_duplicate_or_malformed_responses
    [nil, {}, [{ 'id' => 9 }], [{ 'id' => 1 }, { 'id' => '1' }],
      [{ 'id' => '01' }], [{ 'id' => 1, 'user_answer' => 'One' }],
      [{ 'id' => 1, 'user_answer' => ['A'] }]].each do |responses|
      assert_raises(ListeningSnapshotScorer::InvalidSubmission) { score(responses) }
    end
  end

  def test_rejects_corrupt_or_unsupported_snapshots
    mutations = [->(q) { q['full_score'] = 100 }, ->(q) { q['level'] = 'B1' },
      ->(q) { q['questions']['multiple_choice'][0]['answer'] = 'E' },
      ->(q) { q['questions']['multiple_choice'][1]['id'] = 1 },
      ->(q) { q['questions']['fill_in_the_blanks'] = [{}] }]
    mutations.each do |mutate|
      snapshot = quiz
      mutate.call(snapshot)
      assert_raises(ListeningSnapshotScorer::InvalidQuiz) { score([], snapshot) }
    end
  end

  def test_does_not_mutate_inputs
    snapshot = quiz
    responses = [{ 'id' => 1, 'user_answer' => 'A' }]
    before = Marshal.dump([snapshot, responses])
    score(responses, snapshot)
    assert_equal before, Marshal.dump([snapshot, responses])
  end
end
