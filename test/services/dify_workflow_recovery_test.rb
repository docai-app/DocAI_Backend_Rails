# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'

class DifyWorkflowRecoveryTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  test 'uses GET on original ID and only returns confirmed terminal statuses' do
    id = SecureRandom.uuid
    events = [{ 'event' => 'workflow_started', 'workflow_run_id' => id }]
    %w[succeeded failed stopped running paused unknown].each do |status|
      request = nil
      http = Object.new
      response = Struct.new(:code, :body).new('200', { id: id, status: status, outputs: { text: '{}' } }.to_json)
      http.define_singleton_method(:request) { |value| request = value; response }
      Net::HTTP.stub(:start, ->(*_args, **_options, &block) { block.call(http) }) do
        result = DifyWorkflowRecovery.terminal_events(events, app_key: 'test-only', run_url: 'https://dify.example.test/v1/workflows/run')
        assert_equal 'GET', request.method
        assert_equal "/v1/workflows/run/#{id}", request.path
        assert_equal %w[succeeded failed stopped].include?(status), result.present?
      end
    end
  end

  test 'missing ID never starts another provider request and unknown lookup stays unknown' do
    Net::HTTP.stub(:start, ->(*) { flunk 'must not request without a run ID' }) do
      assert_nil DifyWorkflowRecovery.terminal_events([], app_key: 'test-only', run_url: 'https://dify.example.test/v1/workflows/run')
    end
    Net::HTTP.stub(:start, ->(*) { raise Net::ReadTimeout }) do
      assert_nil DifyWorkflowRecovery.terminal_events([{ 'workflow_run_id' => SecureRandom.uuid }], app_key: 'test-only', run_url: 'https://dify.example.test/v1/workflows/run')
    end
  end
end
