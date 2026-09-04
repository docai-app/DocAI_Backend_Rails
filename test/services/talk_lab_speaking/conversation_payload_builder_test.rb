# frozen_string_literal: true

require 'test_helper'

class TalkLabSpeaking::ConversationPayloadBuilderTest < ActiveSupport::TestCase
  test 'normalizes turns and builds transcript and audio url lists' do
    payload = TalkLabSpeaking::ConversationPayloadBuilder.new(
      {
        turns: [
          { role: 'student', text: 'I want to visit Japan.', audio_url: 'https://cdn/student-1.webm' },
          { role: 'assistant', text: 'What city would you visit first?', audio_url: 'https://cdn/ai-1.webm' }
        ],
        duration_seconds: 42
      }
    ).call

    assert_equal "Student: I want to visit Japan.\nAI: What city would you visit first?", payload['transcript']
    assert_equal ['https://cdn/student-1.webm'], payload['student_audio_urls']
    assert_equal ['https://cdn/ai-1.webm'], payload['ai_audio_urls']
    assert_equal 'ai', payload['turns'].second['role']
    assert_equal 42, payload['duration_seconds']
  end
end
