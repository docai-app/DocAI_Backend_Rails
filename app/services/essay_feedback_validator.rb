# frozen_string_literal: true

# Checks the data contract, not the pedagogical correctness of AI feedback.
class EssayFeedbackValidator
  def self.validate!(outputs, stage:, category:)
    raise ArgumentError, 'Missing workflow output' unless outputs.is_a?(Hash) && outputs['text'].present?

    text = outputs['text']
    if stage == 'grading' && category == 'essay'
      data = AiJsonParser.object(text)
      score = number(data['Overall Score'] || data['overall_score'])
      full = number(data['Full Score'] || data['full_score'])
      raise ArgumentError, 'Invalid overall score' unless score && full && full.positive? && score.between?(0, full)

      criteria = data.select { |key, _| key.match?(/\ACriterion/i) }.values
      raise ArgumentError, 'Missing scoring criteria' if criteria.empty?

      criteria.each do |criterion|
        raise ArgumentError, 'Invalid criterion' unless criterion.is_a?(Hash) && criterion['explanation'].is_a?(String) && criterion['explanation'].present?

        values = criterion.except('Full Score', 'explanation').values
        value = values.length == 1 ? number(values.first) : nil
        maximum = number(criterion['Full Score'])
        raise ArgumentError, 'Invalid criterion score' unless value && maximum && maximum.positive? && value.between?(0, maximum)
      end
      sentences = data.select { |key, _| key.match?(/\Asentence/i) }.values
      raise ArgumentError, 'Missing grammar feedback' if sentences.empty?

      sentences.each do |sentence|
        raise ArgumentError, 'Invalid grammar sentence' unless sentence.is_a?(Hash) && sentence['sentence'].is_a?(String) && sentence['sentence'].present?
        errors = sentence['errors']
        raise ArgumentError, 'Invalid grammar errors' unless errors.is_a?(Hash) || errors.is_a?(Array)
        (errors.is_a?(Hash) ? errors.values : errors).each do |error|
          raise ArgumentError, 'Invalid grammar explanation' unless error.is_a?(Hash) && error['explanation'].is_a?(String) && error['explanation'].present?
        end
      end
    elsif stage == 'general_context'
      data = text.is_a?(Hash) || AiJsonParser.structured?(text) ? AiJsonParser.object(text) : text
      raise ArgumentError, 'Missing feedback content' unless meaningful?(data)
    elsif stage == 'revised_essay'
      raise ArgumentError, 'Missing revised essay' unless text.is_a?(String) && text.present?
    end
    true
  end

  def self.number(value)
    return nil unless value.is_a?(Numeric) || (value.is_a?(String) && value.strip.match?(/\A\d+(?:\.\d+)?\z/))

    number = Float(value)
    number.finite? ? number : nil
  rescue ArgumentError, TypeError
    nil
  end

  def self.meaningful?(value)
    case value
    when String then value.present?
    when Hash then value.values.any? { |v| meaningful?(v) }
    when Array then value.any? { |v| meaningful?(v) }
    else false
    end
  end
end
