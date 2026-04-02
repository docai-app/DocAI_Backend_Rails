# frozen_string_literal: true

require 'test_helper'

class PronunciationIpaTranscriberServiceTest < ActiveSupport::TestCase
  test 'enrich_sentence merges ipa transcript when transcription succeeds' do
    service = PronunciationIpaTranscriberService.new

    service.stub(:transcribe, 'həˈloʊ') do
      result = service.enrich_sentence({ 'sentence' => 'Hello' })

      assert_equal({ 'sentence' => 'Hello', 'ipa_transcript' => 'həˈloʊ' }, result)
    end
  end

  test 'transcribe normalizes local espeak output' do
    service = PronunciationIpaTranscriberService.new

    service.stub(:transcribe_with_espeak_phonemizer, nil) do
      service.stub(:transcribe_with_espeak_ng, "dˈɪd#{PronunciationIpaTranscriberService::ZERO_WIDTH_JOINER}ʒɪɾəl\n") do
        service.stub(:transcribe_with_remote_service, nil) do
          assert_equal 'dˈɪdʒɪɾəl', service.normalize_ipa("dˈɪd#{PronunciationIpaTranscriberService::ZERO_WIDTH_JOINER}ʒɪɾəl")
          assert_equal 'dˈɪdʒɪɾəl', service.transcribe('Digital')
        end
      end
    end
  end

  test 'transcribe falls back to remote service when local engines are unavailable' do
    service = PronunciationIpaTranscriberService.new

    service.stub(:transcribe_with_espeak_phonemizer, nil) do
      service.stub(:transcribe_with_espeak_ng, nil) do
        service.stub(:transcribe_with_remote_service, 'həˈloʊ') do
          assert_equal 'həˈloʊ', service.transcribe('Hello')
        end
      end
    end
  end
end
