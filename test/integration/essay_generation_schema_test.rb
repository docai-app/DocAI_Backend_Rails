# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'
require 'sidekiq/testing'
Sidekiq::Testing.fake!

# Production has both public and tenant-local copies of these table names.
# A public-only test database cannot reproduce a worker silently missing its run.
class EssayGenerationSchemaTest < ActiveSupport::TestCase
  self.fixture_table_names = []
  MODELS = [EssayGenerationRun, EssayOperationEvent, OperationsReportDelivery, EssayGenerationNotification].freeze

  setup do
    @connection = ActiveRecord::Base.connection
    raise 'Isolated test database required' unless ENV['LISTENING_RAILS_ISOLATED_TEST'] == '1' && @connection.pool.db_config.database.start_with?('listening_rails_isolated_test')

    @schema = "generation_shadow_#{SecureRandom.hex(6)}"
    @connection.execute("CREATE SCHEMA #{@connection.quote_table_name(@schema)}")
    MODELS.each do |model|
      table = model.table_name.split('.').last
      @connection.execute("CREATE TABLE #{@connection.quote_table_name(@schema)}.#{table} (LIKE public.#{table} INCLUDING ALL)")
    end
    @user = GeneralUser.create!(email: "schema-#{SecureRandom.hex(6)}@example.test", password: 'Password123!', meta: {}, konnecai_tokens: {})
    @assignment = EssayAssignment.create!(general_user: @user, topic: 'Schema test', title: 'Schema test', assignment: 'Test', category: 'essay', rubric: { 'name' => 'Test' }, meta: {})
    @grading = EssayGrading.create!(general_user: @user, essay_assignment: @assignment, essay: 'Test.', topic: 'Test', status: :draft, grading: {}, meta: {})
    EssayGenerationJob.clear
  end

  test 'worker can claim and finish public run while tenant tables shadow public' do
    run = EssayGenerationRun.request!(@grading, kind: 'grading')
    token = run.token
    service = Object.new
    service.define_singleton_method(:run_workflows) { true }

    with_shadow_schema do
      assert EssayGenerationRun.exists?(run.id), 'worker must not silently miss a public run'
      EssayGradingService.stub(:new, service) do
        EssayGenerationJob.new.perform(run.id, token)
      end
      assert_equal 'ready', run.reload.state
      assert_equal 1, run.attempts
      assert_equal 'graded', @grading.reload.status
      assert_equal 'queued', EssayGenerationRun.find_by!(essay_grading: @grading, kind: 'supplement').state
      assert_not run.claim!(token), 'duplicate delivery must not start another provider call'
      assert_equal 1, run.reload.attempts
      assert_shadow_tables_empty
    end
  end

  test 'generation events report deliveries and notifications stay public under tenant switching' do
    with_shadow_schema do
      MODELS.each { |model| assert_includes Apartment.excluded_models, model.name }
      run = EssayGenerationRun.request!(@grading, kind: 'grading')
      event = EssayOperationEvent.create!(essay_grading: @grading, event: 'schema_test', occurred_at: Time.current)
      report = OperationsReportDelivery.create!(period_start: Time.current - 1.hour, period_end: Time.current)
      notification = EssayGenerationNotification.create!(essay_generation_run: run, token: run.token, kind: 'failed')
      [run, event, report, notification].each do |record|
        table = record.class.table_name.split('.').last
        assert @connection.select_value("SELECT EXISTS(SELECT 1 FROM public.#{table} WHERE id=#{@connection.quote(record.id)})"), "#{table} must write to public"
      end
      assert_equal run.id, notification.reload.essay_generation_run.id
      assert_shadow_tables_empty
    end
  end

  private

  def with_shadow_schema
    Apartment::Tenant.switch(@schema) { yield }
  end

  def assert_shadow_tables_empty
    MODELS.each do |model|
      table = model.table_name.split('.').last
      assert_equal 0, @connection.select_value("SELECT count(*) FROM #{@connection.quote_table_name(@schema)}.#{table}").to_i, "#{table} must not write into a tenant copy"
    end
  end
end
