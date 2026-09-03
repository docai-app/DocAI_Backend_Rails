# frozen_string_literal: true

class SupplementPracticeScoringService
  def initialize(record)
    @record = record
    @questions_data = record.questions_data
    @answers = record.answers
  end

  # 计算分数
  def calculate
    return empty_result unless @questions_data.present?

    @answers ||= {}

    score = 0.0
    full_score = 0.0
    questions_count = 0
    correct_count = 0
    incorrect_count = 0
    details = []

    @questions_data['sections']&.each_with_index do |section, section_index|
      section_type = section['type']
      section_topic = section['topic']
      
      # 找到对应的答案 section
      answer_section = find_answer_section(section_topic, section_type)

      section['questions']&.each_with_index do |question, question_index|
        questions_count += 1
        full_score += 1.0

        # 找到对应的用户答案
        user_answer_data = find_user_answer(answer_section, question, section_type, question_index)
        
        is_correct = check_answer(question, user_answer_data, section_type)
        
        if is_correct
          score += 1.0
          correct_count += 1
        else
          incorrect_count += 1
        end

        details << {
          section_topic: section_topic,
          section_type: section_type,
          question_index: question_index,
          type: section_type,
          is_correct: is_correct,
          user_answer: extract_user_answer_value(user_answer_data, section_type),
          correct_answer: extract_correct_answer(question, section_type)
        }
      end
    end

    {
      score: score,
      full_score: full_score,
      questions_count: questions_count,
      correct_count: correct_count,
      incorrect_count: incorrect_count,
      details: details
    }
  end

  private

  def empty_result
    {
      score: 0.0,
      full_score: 0.0,
      questions_count: 0,
      correct_count: 0,
      incorrect_count: 0,
      details: []
    }
  end

  def find_answer_section(topic, type)
    @answers['sections']&.find do |section|
      section['topic'] == topic && section['type'] == type
    end
  end

  def find_user_answer(answer_section, question, section_type, question_index)
    return nil unless answer_section && answer_section['questions']

    if question['id'].present? && answer_section['questions'].any? { |answer| answer['id'].present? }
      return answer_section['questions'].find { |answer| answer['id'] == question['id'] }
    end

    case section_type
    when 'fill_in_the_blanks'
      # 通过 id 匹配
      answer_section['questions'].find { |q| q['id'] == question['id'] }
    when 'multiple_choice'
      # 通过 question 文本匹配
      answer_section['questions'][question_index] if answer_section['questions'][question_index]&.dig('question') == question['question']
    when 'true_or_false'
      # 通过 statement 文本匹配
      answer_section['questions'][question_index] if answer_section['questions'][question_index]&.dig('statement') == question['statement']
    end
  end

  def check_answer(question, user_answer_data, section_type)
    return false unless user_answer_data

    correct_answer = question['answer']
    user_answer = extract_user_answer_value(user_answer_data, section_type)
    return false if user_answer.nil? || (user_answer.is_a?(String) && user_answer.strip.empty?)

    case section_type
    when 'fill_in_the_blanks'
      # 不区分大小写，去除首尾空格后比较
      normalize_string(user_answer) == normalize_string(correct_answer)
    when 'multiple_choice'
      # 精确匹配（区分大小写）
      user_answer == correct_answer
    when 'true_or_false'
      # 布尔值比较
      !normalize_boolean(user_answer).nil? && normalize_boolean(user_answer) == normalize_boolean(correct_answer)
    else
      false
    end
  end

  def extract_user_answer_value(user_answer_data, section_type)
    return nil unless user_answer_data

    case section_type
    when 'fill_in_the_blanks'
      user_answer_data['user_answer']
    when 'multiple_choice'
      user_answer_data['user_answer']
    when 'true_or_false'
      user_answer_data['user_answer']
    else
      nil
    end
  end

  def extract_correct_answer(question, section_type)
    question['answer']
  end

  def normalize_string(str)
    return '' unless str.is_a?(String)
    str.strip.downcase
  end

  def normalize_boolean(value)
    case value
    when true, 'true', 'True', 'TRUE', 1, '1'
      true
    when false, 'false', 'False', 'FALSE', 0, '0'
      false
    else
      nil
    end
  end
end
