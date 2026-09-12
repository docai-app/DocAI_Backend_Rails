require 'test_helper'
require 'minitest/mock'
require 'sidekiq/testing'
Sidekiq::Testing.fake!

class OperationsReportingTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  # Rails clones schema.rb for each parallel database; schema.rb omits triggers.
  # This is the same explicit installation required after db:schema:load.
  parallelize_setup do |_worker|
    require Rails.root.join('db/migrate/20260912001000_create_operations_reporting').to_s
    ActiveRecord::Migration.suppress_messages { CreateOperationsReporting.new.install_triggers }
  end

  setup do
    @env = ENV.to_h.slice('AI_ENGLISH_REPORTS_ENABLED', 'AI_ENGLISH_REPORTS_ENABLED_AT', 'ADMIN_NOTIFICATION_EMAIL')
    ENV['AI_ENGLISH_REPORTS_ENABLED'] = 'true'
    ENV['ADMIN_NOTIFICATION_EMAIL'] = 'operations@example.test'
    @ending = OperationsReportWindow::ZONE.local(2026, 9, 12, 12)
    ENV['AI_ENGLISH_REPORTS_ENABLED_AT'] = (@ending - 1.hour).iso8601
    @user = GeneralUser.create!(email: "report-#{SecureRandom.hex(4)}@example.test", password: 'Password123!', meta: {}, konnecai_tokens: {})
    @assignment = EssayAssignment.create!(general_user: @user, topic: 'Operations', title: 'Report test', assignment: 'Practice', category: :essay, rubric: { 'name' => 'Test' }, meta: {})
    @assignment.update_columns(created_at: @ending - 1.hour)
    OperationsReportJob.clear
    ActionMailer::Base.deliveries.clear
  end

  teardown do
    %w[AI_ENGLISH_REPORTS_ENABLED AI_ENGLISH_REPORTS_ENABLED_AT ADMIN_NOTIFICATION_EMAIL].each do |key|
      @env.key?(key) ? ENV[key] = @env[key] : ENV.delete(key)
    end
  end

  def grading(status = :graded)
    g = EssayGrading.create!(general_user: @user, essay_assignment: @assignment, topic: 'Operations', essay: 'PRIVATE STUDENT BODY', status: :draft, grading: {}, meta: {})
    g.update_columns(status: EssayGrading.statuses.fetch('pending'))
    EssayOperationEvent.where(essay_grading: g).update_all(occurred_at: @ending - 30.minutes)
    if status != :pending
      g.update_columns(status: EssayGrading.statuses.fetch(status.to_s))
      EssayOperationEvent.where(essay_grading: g, event: status.to_s).update_all(occurred_at: @ending - 28.minutes)
    end
    g
  end

  def report
    OperationsStatusReport.new(beginning: @ending - 12.hours, ending: @ending, now: @ending + 1.minute).call
  end

  test 'three windows exactly cover each civil day without gaps or overlap' do
    z = OperationsReportWindow::ZONE
    endings = [z.local(2026,9,12,12), z.local(2026,9,12,18), z.local(2026,9,13)]
    assert_equal [12,6,6], endings.map { |e| (e - OperationsReportWindow.start_for(e)) / 1.hour }
    assert_equal endings[0], OperationsReportWindow.start_for(endings[1])
    assert_equal endings[1], OperationsReportWindow.start_for(endings[2])
    assert_equal z.local(2026,9,12), OperationsReportWindow.start_for(endings[0])
    assert_equal z.local(2027,1,1), OperationsReportWindow.latest_end(z.local(2027,1,1,1))
    assert_raises(ArgumentError) { OperationsReportWindow.start_for(z.local(2026,9,12,13)) }
  end

  test 'delayed scheduler catches missed windows and respects activation' do
    due = OperationsReportWindow.due_ends(since: @ending, now: @ending + 13.hours)
    assert_equal [@ending, @ending+6.hours, @ending+12.hours], due
    assert_empty OperationsReportWindow.due_ends(since: @ending+1.minute, now: @ending)
  end

  test 'database telemetry observes update_columns and survives clearing error metadata' do
    g = grading(:stopped)
    g.clear_grading_errors!
    g.update_columns(status: EssayGrading.statuses[:pending])
    g.update_columns(status: EssayGrading.statuses[:graded])
    assert_equal 1, EssayOperationEvent.where(essay_grading: g, event: 'submitted').count
    assert_equal 1, EssayOperationEvent.where(essay_grading: g, event: 'stopped').count
    assert_equal 1, EssayOperationEvent.where(essay_grading: g, event: 'graded').count
    assert_empty g.reload.meta
  end

  test 'draft creation is not a submission and later submission is counted at transition' do
    g = EssayGrading.create!(general_user: @user, essay_assignment: @assignment, topic: 'Operations', status: :draft, grading: {}, meta: {})
    assert_empty EssayOperationEvent.where(essay_grading: g, event: 'submitted')
    assert_equal 0, report['submission_count']
    g.update_columns(status: EssayGrading.statuses[:pending])
    EssayOperationEvent.where(essay_grading: g, event: 'submitted').update_all(occurred_at: @ending - 1.minute)
    assert_equal 1, report['submission_count']
  end

  test 'mean uses completion events and never updated_at' do
    g = grading
    g.update_columns(updated_at: @ending + 3.days)
    r = report
    assert_equal 1, r['submission_count']
    assert_equal 120.0, r['schools'].first['average_seconds']
    assert_equal 120.0, r['schools'].first['p95_seconds']
    assert_equal 1, r['schools'].first['duration_samples']
    assert_equal '學校未確認', r['schools'].first['name']
  end

  test 'legacy missing history is counted explicitly without invented duration' do
    g = grading
    EssayOperationEvent.where(essay_grading: g).delete_all
    g.update_columns(created_at: @ending - 1.hour)
    r = report
    assert_equal 1, r['legacy_submission_count']
    assert_nil r['schools'].first['average_seconds']
    assert_equal 1, r['schools'].first['missing_duration']
  end

  test 'recovered failures survive rerun and appear separately from current stopped' do
    g = grading(:stopped)
    g.update_columns(status: EssayGrading.statuses[:graded])
    EssayOperationEvent.where(essay_grading: g, event: 'graded').update_all(occurred_at: @ending - 1.minute)
    b = report['schools'].first
    assert_equal 1, b['error_records']
    assert_equal 1, b['recovered']
    assert_equal 0, b['stopped']
  end

  test 'cross-period backlog is shown but recent pending is not falsely called stuck' do
    old = grading(:pending)
    old.update_columns(created_at: @ending - 3.days)
    EssayOperationEvent.where(essay_grading: old, event: 'pending').update_all(occurred_at: @ending - 3.hours)
    recent = grading(:pending)
    r = report
    assert_equal [old.id], r['alerts'].map { |x| x['id'] }
    assert_equal 'pending', recent.reload.status
    assert_equal 'pending', old.reload.status
  end

  test 'unknown and failed supplements are urgent even when main graded' do
    g = grading
    run = EssayGenerationRun.create!(essay_grading: g, kind: 'supplement', state: 'unknown', token: SecureRandom.uuid, attempts: 1)
    assert_match '結果不明', report['alerts'].first['reason']
    run.update!(state: 'failed')
    assert_match '補充練習失敗', report['alerts'].first['reason']
    assert_equal 'graded', g.reload.status
  end

  test 'exclusive endpoint prevents double counting a submission at noon' do
    g = grading(:pending)
    EssayOperationEvent.where(essay_grading: g, event: 'submitted').update_all(occurred_at: @ending)
    assert_equal 0, report['submission_count']
    after = OperationsStatusReport.new(beginning: @ending, ending: @ending+6.hours, now: @ending+6.hours).call
    assert_equal 1, after['submission_count']
  end

  test 'stale supplement is reported even when main grading succeeded' do
    g = grading
    EssayGenerationRun.create!(essay_grading: g, kind: 'supplement', state: 'running', token: SecureRandom.uuid, attempts: 1, started_at: @ending - 3.hours)
    alert = report['alerts'].find { |row| row['id'] == g.id }
    assert_includes alert['reason'], '補充練習超過 2 小時'
    assert_equal 'graded', g.reload.status
  end

  test 'recent queue dispatch overrides an old pending event for backlog age' do
    g = grading(:pending)
    g.update_columns(created_at: @ending - 3.days)
    EssayOperationEvent.where(essay_grading: g, event: 'pending').update_all(occurred_at: @ending - 3.days)
    EssayGenerationRun.create!(essay_grading: g, kind: 'grading', state: 'queued', token: SecureRandom.uuid, queued_at: @ending - 1.minute)
    assert_empty report['alerts']
  end

  test 'trigger records absolute event time independently of database session timezone' do
    connection = ActiveRecord::Base.connection
    original = connection.select_value('SHOW TIMEZONE')
    %w[UTC Asia/Macau].each do |zone|
      connection.execute("SET TIME ZONE '#{zone}'")
      before = Time.current
      g = EssayGrading.create!(general_user: @user, essay_assignment: @assignment, status: :draft, topic: 'Clock', grading: {}, meta: {})
      g.update_columns(status: EssayGrading.statuses[:pending])
      event = EssayOperationEvent.find_by!(essay_grading: g, event: 'submitted')
      assert_in_delta Time.current.to_f, event.occurred_at.to_f, 2
      # PostgreSQL and Ruby clocks can differ by milliseconds; this is a timezone
      # regression (eight hours), not a cross-process clock synchronisation test.
      assert_includes EssayOperationEvent.where(occurred_at: (before - 1.second)..(Time.current + 1.second)).pluck(:id), event.id
    end
  ensure
    connection.execute("SET TIME ZONE #{connection.quote(original)}") if original
  end

  test 'notification transport uncertainty is shown prominently without sending again' do
    g = grading(:stopped)
    run = EssayGenerationRun.create!(essay_grading: g, kind: 'grading', state: 'failed', token: SecureRandom.uuid)
    mail = Object.new
    def mail.message; Struct.new(:encoded).new('rendered'); end
    def mail.deliver_now; raise IOError, 'disconnected'; end
    AdminNotificationMailer.stub(:assignment_stopped_notification, mail) do
      2.times { EssayGenerationNotificationJob.new.perform(run.id, run.token) }
    end
    assert_equal 'unknown', EssayGenerationNotification.find_by!(essay_generation_run: run).state
    assert run.reload.notified_at
    assert report['alerts'].any? { |row| row['reason'] == '錯誤通知郵件未確認寄達' }
  end

  test 'notification render failure can retry without consuming transport claim' do
    g = grading(:stopped)
    run = EssayGenerationRun.create!(essay_grading: g, kind: 'grading', state: 'failed', token: SecureRandom.uuid)
    AdminNotificationMailer.stub(:assignment_stopped_notification, ->(*) { raise ArgumentError, 'render failed' }) do
      assert_raises(ArgumentError) { EssayGenerationNotificationJob.new.perform(run.id, run.token) }
    end
    assert_nil run.reload.notified_at
    assert_equal 'build_failed', EssayGenerationNotification.find_by!(essay_generation_run: run).state
    EssayGenerationNotificationJob.new.perform(run.id, run.token)
    assert_equal 'sent', EssayGenerationNotification.find_by!(essay_generation_run: run).state
    assert_equal 1, ActionMailer::Base.deliveries.length
  end

  test 'email highlights intervention and does not include student content or unescaped markup' do
    grading(:stopped)
    @assignment.update_columns(title: '<script>alert(1)</script>')
    message = AdminNotificationMailer.operations_status_report(report).message
    assert_equal ['operations@example.test'], message.to
    assert_includes message.subject, '需人工處理'
    html = message.html_part.decoded
    assert_operator html.index('需要人工處理'), :<, html.index('整體摘要')
    assert_not_includes html, '<script>'
    assert_not_includes message.encoded, 'PRIVATE STUDENT BODY'
    assert_includes message.text_part.decoded, '需要人工處理'
    assert_includes html, "assignmentId=#{@assignment.id}"
  end

  test 'duplicate report jobs send only one message for a fixed window' do
    grading
    2.times { OperationsReportJob.new.perform(@ending.iso8601) }
    assert_equal 1, ActionMailer::Base.deliveries.length
    assert_equal 'sent', OperationsReportDelivery.find_by!(period_end: @ending).state
    assert_equal 1, OperationsReportDelivery.where(period_end: @ending).count
  end

  test 'SMTP ambiguous failure is not automatically resent and is prominent in next report' do
    message = Object.new
    def message.encoded; 'test'; end
    def message.deliver!; raise IOError, 'transport disconnected'; end
    delivery = Struct.new(:message).new(message)
    AdminNotificationMailer.stub(:operations_status_report, delivery) do
      2.times { OperationsReportJob.new.perform(@ending.iso8601) }
    end
    assert_equal 'unknown', OperationsReportDelivery.find_by!(period_end: @ending).state
    later = OperationsStatusReport.new(beginning: @ending, ending: @ending + 6.hours, now: @ending+6.hours).call
    assert_equal 1, later['alert_count']
    assert_includes later['alerts'].first['reason'], '未確認寄達'
  end

  test 'disabled switch suppresses both scheduler and queued deliveries' do
    ENV['AI_ENGLISH_REPORTS_ENABLED'] = 'false'
    OperationsReportTickJob.new.perform
    OperationsReportJob.new.perform(@ending.iso8601)
    assert_empty OperationsReportJob.jobs
    assert_empty ActionMailer::Base.deliveries
  end

  test 'generation attempts retain an append-only event independent of resettable run state' do
    g = grading
    run = EssayGenerationRun.create!(essay_grading: g, kind: 'grading', state: 'running', token: SecureRandom.uuid, attempts: 1)
    run.update!(state: 'retry_wait', token: SecureRandom.uuid)
    run.update!(state: 'running', attempts: 2)
    assert_equal [1], EssayOperationEvent.where(essay_grading: g, event: 'generation_retry_wait').pluck(:attempts)
  end

  test 'error stage survives clear without storing raw error message or student body' do
    g = grading
    g.record_grading_error!(stage: 'speaking_scoring', message: 'PRIVATE ERROR AND STUDENT BODY')
    g.clear_grading_errors!
    event = EssayOperationEvent.find_by!(essay_grading: g, event: 'error')
    assert_equal 'speaking_scoring', event.kind
    assert_not_includes event.attributes.to_json, 'PRIVATE ERROR'
  end

  test 'submission attribution uses submission school rather than assignment school' do
    a = School.create!(name: "Owner #{SecureRandom.hex(4)}", code: SecureRandom.hex(4))
    b = School.create!(name: "Student #{SecureRandom.hex(4)}", code: SecureRandom.hex(4))
    year = SchoolAcademicYear.create!(school: a, name: '2026-2027', start_date: '2026-08-01', end_date: '2027-07-31')
    @assignment.update_columns(school_academic_year_id: year.id)
    g = grading
    g.update_columns(submission_school_id: b.id)
    buckets = report['schools'].index_by { |row| row['name'] }
    assert_equal 1, buckets[a.name]['assignments']
    assert_equal 0, buckets[a.name]['submissions']
    assert_equal 1, buckets[b.name]['submissions']
  end

  test 'Listening is excluded without modifying its workflow' do
    @assignment.update_columns(category: EssayAssignment.categories.fetch('listening'))
    r = report
    assert_equal 0, r['assignment_count']
    assert_equal 0, r['submission_count']
  end

  test 'telemetry rolls back with business writes' do
    g = grading
    count = EssayOperationEvent.where(essay_grading: g).count
    EssayGrading.transaction(requires_new: true) do
      g.update_columns(status: EssayGrading.statuses[:stopped])
      raise ActiveRecord::Rollback
    end
    assert_equal count, EssayOperationEvent.where(essay_grading: g).count
    assert_equal 'graded', g.reload.status
  end

  test 'build failure does not claim email and can recover safely' do
    OperationsStatusReport.stub(:new, ->(**_) { raise 'database unavailable' }) do
      assert_raises(RuntimeError) { OperationsReportJob.new.perform(@ending.iso8601) }
    end
    row = OperationsReportDelivery.find_by!(period_end: @ending)
    assert_equal 'build_failed', row.state
    assert_nil row.claimed_at
    OperationsReportJob.new.perform(@ending.iso8601)
    assert_equal 'sent', row.reload.state
    assert_equal 1, ActionMailer::Base.deliveries.length
  end

  test 'scheduler uses fixed cutoff payloads and does not requeue sent or unknown reports' do
    travel_to(@ending + 1.minute) { OperationsReportTickJob.new.perform }
    assert_equal [@ending.iso8601], OperationsReportJob.jobs.first['args']
    OperationsReportDelivery.create!(period_start: @ending-12.hours, period_end: @ending, state: 'unknown')
    OperationsReportJob.clear
    travel_to(@ending + 1.minute) { OperationsReportTickJob.new.perform }
    assert_empty OperationsReportJob.jobs
  end
end
