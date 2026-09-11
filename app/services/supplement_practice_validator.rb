# frozen_string_literal: true

class SupplementPracticeValidator
  def self.parse(grading)
    questions = SupplementPracticeParserService.new(grading).parse
    return nil unless questions

    answers = questions.deep_dup
    answers['sections'].each do |section|
      section['questions'].each { |question| question['user_answer'] = question['answer'] }
    end
    record = Struct.new(:questions_data, :answers)
    correct = SupplementPracticeScoringService.new(record.new(questions, answers)).calculate
    blank = SupplementPracticeScoringService.new(record.new(questions, {})).calculate
    count = questions['sections'].sum { |section| section['questions'].length }
    unless count.positive? && correct[:score] == count && correct[:full_score] == count &&
           blank[:score] == 0 && blank[:full_score] == count
      raise ArgumentError, 'Exercise scoring contract is incomplete'
    end
    questions
  end
end
