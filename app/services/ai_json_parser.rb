# frozen_string_literal: true

require 'json'

# Only unwrap transport decoration. Never repair/truncate JSON or remove backticks
# inside a value: that could silently change a grade, answer or explanation.
class AiJsonParser
  def self.parse(value)
    4.times do
      return value if value.is_a?(Hash) || value.is_a?(Array)
      raise JSON::ParserError, 'Expected structured feedback' unless value.is_a?(String)

      value = value.strip.sub(/\A\uFEFF/, '').strip
      if value.start_with?('`')
        value = value.sub(/\A`+[ \t]*(?:json\b)?\s*/i, '').sub(/\s*`+\z/, '').strip
      end
      value = JSON.parse(value)
    end
    return value if value.is_a?(Hash) || value.is_a?(Array)

    raise JSON::ParserError, 'Expected structured feedback'
  end

  def self.object(value)
    result = parse(value)
    raise JSON::ParserError, 'Expected a feedback object' unless result.is_a?(Hash)

    result
  end

  def self.structured?(value)
    return true unless value.is_a?(String)
    return true if value.lstrip.match?(/\A(?:\uFEFF\s*)?[`\[{"]/)

    # Valid scalar JSON is not a legacy worksheet either.
    JSON.parse(value)
    true
  rescue JSON::ParserError
    false
  end
end
