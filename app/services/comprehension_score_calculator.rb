# frozen_string_literal: true

# The denominator belongs to the enabled questions, never to the answers supplied.
# Deliberately pure: auditing old submissions must not change stored grades.
class ComprehensionScoreCalculator
  def self.call(questions, fill_in_the_blanks_visible:)
    score = 0
    full_score = 0
    Array(questions).each do |question|
      next unless question.is_a?(Hash)

      if question['type'] == 'fill_in_the_blanks'
        next unless fill_in_the_blanks_visible

        blanks = Array(question['blanks'])
        full_score += blanks.length
        answers = parse_answers(question['user_answer'])
        # Iterate trusted blanks rather than user keys: extra IDs cannot earn marks.
        blanks.each do |blank|
          next unless blank.is_a?(Hash)

          correct = blank['answer'].to_s.strip.downcase
          actual = answers[blank['id']].to_s.strip.downcase
          score += 1 if !correct.empty? && !actual.empty? && correct == actual
        end
      else
        full_score += 1
        actual = question['user_answer']
        correct = question['answer']
        score += 1 if !actual.nil? && !correct.nil? && actual == correct
      end
    end
    { score: score, full_score: full_score, questions_count: full_score }
  end

  def self.parse_answers(value)
    result = value.is_a?(String) ? JSON.parse(value) : value
    result.is_a?(Hash) ? result : {}
  rescue JSON::ParserError
    {}
  end
  private_class_method :parse_answers
end
