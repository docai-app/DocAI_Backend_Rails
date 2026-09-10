# frozen_string_literal: true

# The caller MUST load quiz from a private, server-owned assignment snapshot,
# never from request parameters. This service deliberately does not load records
# or replace the legacy grading callback until that persistence path is wired.
class ListeningSnapshotScorer
  class InvalidQuiz < StandardError; end
  class InvalidSubmission < StandardError; end

  COUNTS = { 'A2' => 4, 'B2' => 6, 'C2' => 6 }.freeze
  OPTIONS = %w[A B C D].freeze

  def self.call(quiz:, responses:)
    new.call(quiz: quiz, responses: responses)
  end

  def call(quiz:, responses:)
    rows = validate_quiz(quiz)
    answers = validate_responses(responses, rows.map { |row| row.fetch('id').to_s })
    results = rows.map do |row|
      selected = answers[row.fetch('id').to_s]
      correct = selected == row.fetch('answer')
      # Do not return the answer key, transcript, evidence or client metadata.
      { 'id' => row.fetch('id'), 'user_answer' => selected,
        'is_correct' => correct, 'score' => correct ? 1 : 0 }
    end
    score = results.sum { |row| row.fetch('score') }
    { 'questions' => results, 'score' => score, 'full_score' => rows.length,
      'percentage' => (100.0 * score / rows.length).round }
  end

  private

  def validate_quiz(quiz)
    raise InvalidQuiz, 'Invalid listening snapshot' unless quiz.is_a?(Hash)

    count = COUNTS[quiz['level']]
    groups = quiz['questions']
    raise InvalidQuiz, 'Unsupported listening question groups' unless groups.is_a?(Hash) &&
      groups.keys.sort == %w[fill_in_the_blanks multiple_choice] && groups['fill_in_the_blanks'] == []

    rows = groups['multiple_choice']
    raise InvalidQuiz, 'Invalid listening question count' unless count && rows.is_a?(Array) &&
      rows.length == count && quiz['full_score'] == count

    rows.each_with_index do |row, index|
      raise InvalidQuiz, 'Invalid listening question' unless row.is_a?(Hash) &&
        row['id'] == index + 1 && row['type'] == 'multiple_choice' &&
        row['options'].is_a?(Hash) && row['options'].keys.sort == OPTIONS &&
        row['options'].values.all? { |value| value.is_a?(String) && !value.strip.empty? } &&
        OPTIONS.include?(row['answer'])
    end
    rows
  end

  def validate_responses(responses, ids)
    raise InvalidSubmission, 'Responses must be an array' unless responses.is_a?(Array) && responses.length <= ids.length

    responses.each_with_object({}) do |row, result|
      raise InvalidSubmission, 'Invalid response' unless row.is_a?(Hash) &&
        (row['id'].is_a?(Integer) || row['id'].is_a?(String))

      id = row['id'].to_s
      raise InvalidSubmission, 'Unknown or duplicate question' unless ids.include?(id) && !result.key?(id)

      answer = row['user_answer']
      # Only option labels are accepted; never normalize arbitrary option text.
      raise InvalidSubmission, 'Invalid answer option' unless answer.nil? || answer == '' || OPTIONS.include?(answer)

      result[id] = answer == '' ? nil : answer
    end
  end
end
