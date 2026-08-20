# frozen_string_literal: true

require 'test_helper'

class EssayOcrMoonshotServiceTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  setup do
    @original_environment = ENV.to_h.slice('MOONSHOT_API_KEY', 'MOONSHOT_BASE_URL', 'MOONSHOT_MODEL')
    ENV['MOONSHOT_API_KEY'] = 'test-moonshot-key'
    ENV['MOONSHOT_BASE_URL'] = 'https://api.moonshot.cn/v1'
    ENV['MOONSHOT_MODEL'] = 'kimi-k2.6'
  end

  teardown do
    %w[MOONSHOT_API_KEY MOONSHOT_BASE_URL MOONSHOT_MODEL].each { |key| ENV.delete(key) }
    @original_environment.each { |key, value| ENV[key] = value }
  end

  test 'sends compressed image data to Kimi and returns only the transcript' do
    captured = nil
    requester = lambda do |**options|
      captured = options
      Struct.new(:body).new({ choices: [{ message: { content: "  Original essay text.\n" } }] }.to_json)
    end
    image = Base64.strict_encode64("\xFF\xD8\xFFsmall-image".b)
    service = EssayOcr::MoonshotService.new(request_id: 'ocr-request-1', requester: requester)

    result = service.call(images: [{ dataUrl: "data:image/jpeg;base64,#{image}" }])

    assert_equal 'Original essay text.', result
    assert_equal 'https://api.moonshot.cn/v1/chat/completions', captured[:url]
    assert_equal 'Bearer test-moonshot-key', captured.dig(:headers, :authorization)
    payload = JSON.parse(captured[:payload])
    assert_equal 'kimi-k2.6', payload['model']
    assert_equal({ 'type' => 'disabled' }, payload['thinking'])
    assert_not payload.key?('temperature'), 'K2.6 instant mode should use the provider-managed temperature (0.6)'
    assert_equal "data:image/jpeg;base64,#{image}", payload.dig('messages', 1, 'content', 1, 'image_url', 'url')
  end

  test 'rejects unsupported or malformed files before calling Moonshot' do
    called = false
    requester = lambda do |**_options|
      called = true
    end
    service = EssayOcr::MoonshotService.new(requester: requester)

    error = assert_raises(EssayOcr::MoonshotService::Error) do
      service.call(images: [{ dataUrl: 'data:application/pdf;base64,AAAA' }])
    end

    assert_equal 'ESSAY_OCR_INVALID_IMAGE', error.error_code
    assert_not called
  end

  test 'rejects image data that does not match the declared MIME type' do
    service = EssayOcr::MoonshotService.new(requester: ->(**_options) { flunk 'Moonshot must not be called' })
    fake_png = Base64.strict_encode64("\xFF\xD8\xFFnot-a-png".b)

    error = assert_raises(EssayOcr::MoonshotService::Error) do
      service.call(images: [{ dataUrl: "data:image/png;base64,#{fake_png}" }])
    end

    assert_equal 'ESSAY_OCR_INVALID_IMAGE', error.error_code
  end

  test 'fails closed when the Moonshot key is missing' do
    ENV.delete('MOONSHOT_API_KEY')
    image = Base64.strict_encode64("\x89PNG\r\n\x1A\nsmall-image".b)
    service = EssayOcr::MoonshotService.new(requester: ->(**_options) { flunk 'Moonshot must not be called' })

    error = assert_raises(EssayOcr::MoonshotService::Error) do
      service.call(images: [{ dataUrl: "data:image/png;base64,#{image}" }])
    end

    assert_equal 503, error.http_status
    assert_equal 'ESSAY_OCR_CONFIG_ERROR', error.error_code
  end
end
