# frozen_string_literal: true

require 'json'

class SupplementPracticeParserService
  def initialize(essay_grading)
    @essay_grading = essay_grading
  end

  # 解析 supplement_practice text 字段中的 JSON 数据
  def parse
    supplement_practice_data = @essay_grading.grading['supplement_practice']
    return nil unless supplement_practice_data.present?

    text_content = supplement_practice_data['text']
    return nil unless text_content.present?

    begin
      # 解析 JSON 字符串
      parsed_data = JSON.parse(text_content)
      
      # 验证数据结构
      validate_structure(parsed_data)
      
      # 规范化数据（为题目生成 ID 等）
      normalized_data = normalize_data(parsed_data)
      
      normalized_data
    rescue JSON::ParserError => e
      Rails.logger.error("[SupplementPracticeParserService] JSON parse error: #{e.message}")
      raise ArgumentError, "Invalid JSON format: #{e.message}"
    rescue StandardError => e
      Rails.logger.error("[SupplementPracticeParserService] Parse error: #{e.message}")
      raise e
    end
  end

  # 为学生端返回题目数据（不包含正确答案）
  def parse_for_student
    parsed_data = parse
    return nil unless parsed_data

    # 移除所有答案字段
    student_data = deep_dup(parsed_data)
    # remove_answers(student_data)
    student_data
  end

  private

  def validate_structure(data)
    unless data.is_a?(Hash)
      raise ArgumentError, 'Data must be a Hash'
    end

    # 验证 sections 数组
    unless data['sections'].is_a?(Array)
      raise ArgumentError, 'Data must contain a "sections" array'
    end

    # 验证每个 section
    data['sections'].each_with_index do |section, section_index|
      validate_section(section, section_index)
    end
  end

  def validate_section(section, section_index)
    unless section.is_a?(Hash)
      raise ArgumentError, "Section #{section_index} must be a Hash"
    end

    unless %w[multiple_choice true_or_false fill_in_the_blanks].include?(section['type'])
      raise ArgumentError, "Section #{section_index} has invalid type: #{section['type']}"
    end

    unless section['questions'].is_a?(Array)
      raise ArgumentError, "Section #{section_index} must have a 'questions' array"
    end

    # 验证题目
    section['questions'].each_with_index do |question, question_index|
      validate_question(question, section['type'], section_index, question_index)
    end
  end

  def validate_question(question, type, section_index, question_index)
    unless question.is_a?(Hash)
      raise ArgumentError, "Question #{section_index}-#{question_index} must be a Hash"
    end

    case type
    when 'multiple_choice'
      raise ArgumentError, "Question #{section_index}-#{question_index} missing 'question' field" unless question['question'].present?
      raise ArgumentError, "Question #{section_index}-#{question_index} missing 'options' array" unless question['options'].is_a?(Array)
      raise ArgumentError, "Question #{section_index}-#{question_index} missing 'answer'" unless question['answer'].present?
    when 'true_or_false'
      raise ArgumentError, "Question #{section_index}-#{question_index} missing 'statement' field" unless question['statement'].present?
      raise ArgumentError, "Question #{section_index}-#{question_index} missing 'answer'" unless question.key?('answer')
    when 'fill_in_the_blanks'
      raise ArgumentError, "Question #{section_index}-#{question_index} missing 'question' field" unless question['question'].present?
      raise ArgumentError, "Question #{section_index}-#{question_index} missing 'answer'" unless question['answer'].present?
    end
  end

  def normalize_data(data)
    normalized = deep_dup(data)
    
    # 为每个题目生成唯一 ID（如果不存在）
    normalized['sections'].each_with_index do |section, section_index|
      section['questions'].each_with_index do |question, question_index|
        # 对于 fill_in_the_blanks，如果已有 id，保留；否则生成新 id
        if section['type'] == 'fill_in_the_blanks'
          question['id'] ||= "blank_#{section_index}_#{question_index}"
        else
          # 为 multiple_choice 和 true_or_false 生成 ID
          question['id'] = "question_#{section_index}_#{question_index}"
        end
      end
    end
    
    normalized
  end

  def remove_answers(data)
    data['sections'].each do |section|
      section['questions'].each do |question|
        question.delete('answer')
      end
    end
  end

  def deep_dup(obj)
    case obj
    when Hash
      obj.transform_values { |v| deep_dup(v) }
    when Array
      obj.map { |v| deep_dup(v) }
    else
      obj.dup rescue obj
    end
  end
end
