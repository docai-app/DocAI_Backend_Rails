# frozen_string_literal: true

require 'digest'
require 'json'

# Stable across JSON object key ordering, but not changed answers or intent.
class ListeningSubmissionFingerprint
  def self.call(payload)
    Digest::SHA256.hexdigest(JSON.generate(canonical(payload)))
  end

  def self.canonical(value)
    case value
    when Hash
      value.stringify_keys.sort.to_h.transform_values { |child| canonical(child) }
    when Array
      value.map { |child| canonical(child) }
    else
      value
    end
  end
  private_class_method :canonical
end
