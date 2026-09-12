# Read-only reporting: never reruns, cancels, or changes grading state.
class OperationsStatusReport
  ROW_LIMIT = 5_000
  ALERT_LIMIT = 100
  WARNING_AGE = 2.hours

  def initialize(beginning:, ending:, now: Time.current)
    @beginning, @ending, @now = beginning, ending, now
    @warnings = []
  end

  def call
    self.class.verify_capture!
    assignments_scope = EssayAssignment.where.not(category: :listening).where(created_at: @beginning...@ending)
    assignments = bounded(assignments_scope.includes(:general_user, school_academic_year: :school), '建立作業明細')
    submitted_ids = EssayOperationEvent.where(event: 'submitted').group(:essay_grading_id)
      .having('MIN(occurred_at) >= ? AND MIN(occurred_at) < ?', @beginning.iso8601(6), @ending.iso8601(6)).select(:essay_grading_id)
    legacy = base.where(created_at: @beginning...@ending).where.not(status: :draft)
      .where.not(id: EssayOperationEvent.where(event: 'submitted').select(:essay_grading_id))
    submissions_scope = base.where(id: submitted_ids).or(legacy)
    submissions = bounded(with_context(submissions_scope), '提交統計')
    @events = event_groups(submissions.map(&:id))
    schools = {}
    types = {}
    overall = bucket_for('全部')
    submissions.each do |g|
      key, name = submission_school(g)
      bucket = (schools[key] ||= bucket_for(name))
      type = (types[g.essay_assignment.category] ||= bucket_for(g.essay_assignment.category))
      [bucket, type, overall].each { |b| add_submission(b, g) }
    end
    created = assignments.map do |a|
      school = a.school_academic_year&.school
      key = school&.id || 'unknown'
      (schools[key] ||= bucket_for(school&.name || '學校未確認'))[:assignments] += 1
      (types[a.category] ||= bucket_for(a.category))[:assignments] += 1
      { school: school&.name || '學校未確認', teacher: a.general_user&.nickname.presence || '老師名稱未提供',
        title: a.title, category: a.category, academic_year: a.school_academic_year&.name,
        created_at: a.created_at.iso8601, url: assignment_url(a.id) }
    end
    alerts = notification_alerts + collect_alerts
    period_events = EssayOperationEvent.where(occurred_at: @beginning...@ending).where(essay_grading_id: base.select(:id))
    failed_ids = period_events.where(event: %w[error stopped generation_failed generation_retry_wait]).select(:essay_grading_id)
    main_failed_ids = period_events.where(event: 'stopped').or(period_events.where(event: %w[generation_failed generation_retry_wait], kind: 'grading')).select(:essay_grading_id)
    delivery_problems = OperationsReportDelivery.where.not(period_end: @ending)
      .where(state: %w[unknown build_failed]).or(OperationsReportDelivery.where.not(period_end: @ending)
        .where(state: 'delivering').where('claimed_at < ?', @now - 15.minutes))
    delivery_problems.order(:period_end).limit(20).each do |d|
      alerts << { reason: '之前的報告未確認寄達', title: d.period_end.in_time_zone('Asia/Macau').strftime('%F %R'),
        action: '請工程師核對郵件傳送紀錄；不要直接重寄，避免重複郵件。' }
    end
    @warnings << '有未確認的歷史報告寄送問題，最多列出 20 份。' if delivery_problems.count > 20
    if ENV['AI_ENGLISH_REPORTS_ENABLED_AT'].present?
      start = Time.iso8601(ENV['AI_ENGLISH_REPORTS_ENABLED_AT'])
      last = OperationsReportDelivery.where(state: 'sent').maximum(:period_end) || start
      @warnings << '報告中斷超過 7 天；自動補報只涵蓋最近 7 天，更早時段須人工核對。' if last < @now - 7.days
    end
    {
      period_start: @beginning.iso8601, period_end: @ending.iso8601, snapshot_at: @now.iso8601,
      assignment_count: assignments_scope.count, teacher_count: assignments_scope.distinct.count(:general_user_id),
      submission_count: submissions_scope.count, status_counts: submissions_scope.group(:status).count,
      period_error_records: base.where(id: failed_ids).count,
      period_recovered_main: base.where(id: main_failed_ids, status: :graded).count,
      period_supplement_failed: period_events.where(event: 'generation_failed', kind: 'supplement').distinct.count(:essay_grading_id),
      completion: finalize(overall),
      legacy_submission_count: legacy.count,
      schools: schools.values.map { |b| finalize(b) }, types: types.values.map { |b| finalize(b) },
      assignments: created, alerts: alerts.first(ALERT_LIMIT), alert_count: alerts.length,
      warnings: @warnings, definitions: [
        '統計時段含起點、不含終點。提交以首次正式提交時間計算；草稿不算，重跑不算新提交。',
        '狀態是產生報告當刻的快照；遲到補報可能包含時段結束後才完成的批改。',
        '完成時間＝首次正式提交至首次 graded（含等待）；沒有可信事件的舊紀錄不計入平均。',
        '整體錯誤摘要涵蓋本時段所有失敗事件（含舊提交）；分組的曾失敗／恢復則以本時段提交群體計算。舊版已清除的歷史無法復原。',
        '跨時段未解決的 stopped、疑似長時間 pending、結果不明及練習失敗會重複提醒直到處理。',
        'Listening 不在本輪統計範圍。學校不使用老師目前所屬學校猜測；未能確認時另外列出。'
      ]
    }.deep_stringify_keys
  end

  private

  def self.verify_capture!
    count = ActiveRecord::Base.connection.select_value(<<~SQL).to_i
      SELECT COUNT(*) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
      JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='public' AND t.tgenabled IN ('O','A')
      AND ((c.relname='essay_gradings' AND t.tgname='essay_operations_status')
        OR (c.relname='essay_generation_runs' AND t.tgname='essay_operations_generation'))
    SQL
    raise 'Operations event capture unavailable; apply migration or restore reporting triggers' unless count == 2
  end

  def base
    EssayGrading.joins(:essay_assignment).where.not(essay_assignments: { category: EssayAssignment.categories.fetch('listening') })
  end

  def with_context(scope)
    scope.includes(:submission_school, :submission_academic_year, essay_assignment: { school_academic_year: :school })
  end

  def bounded(scope, label)
    rows = scope.limit(ROW_LIMIT + 1).to_a
    @warnings << "#{label}超過 #{ROW_LIMIT} 筆，明細／分組指標不完整；請人工匯出核對。" if rows.length > ROW_LIMIT
    rows.first(ROW_LIMIT)
  end

  def event_groups(ids)
    EssayOperationEvent.where(essay_grading_id: ids).where('occurred_at <= ?', @now.iso8601(6)).order(:occurred_at).group_by(&:essay_grading_id)
  end

  def submission_school(g)
    school = g.submission_school || g.submission_academic_year&.school
    return [school.id, school.name] if school
    # Do not silently assign a submission to its teacher's school or infer from dates.
    ['unknown', '學校未確認']
  end

  def bucket_for(name)
    { name: name, assignments: 0, submissions: 0, graded: 0, pending: 0, stopped: 0, draft: 0,
      error_records: 0, recovered: 0, durations: [], supplement_durations: [], missing_duration: 0 }
  end

  def add_submission(b, g)
    b[:submissions] += 1
    b[g.status.to_sym] += 1
    events = @events[g.id] || []
    failed = events.any? { |e| %w[error stopped generation_failed generation_retry_wait].include?(e.event) && e.occurred_at >= @beginning && e.occurred_at < @ending }
    b[:error_records] += 1 if failed
    main_failure = events.any? do |e|
      e.occurred_at >= @beginning && e.occurred_at < @ending &&
        (e.event == 'stopped' || (%w[generation_failed generation_retry_wait].include?(e.event) && e.kind == 'grading'))
    end
    b[:recovered] += 1 if main_failure && g.graded?
    submitted = events.find { |e| e.event == 'submitted' }&.occurred_at
    completed = submitted && events.find { |e| e.event == 'graded' && e.occurred_at >= submitted }&.occurred_at
    if completed
      b[:durations] << (completed - submitted)
    elsif g.graded?
      b[:missing_duration] += 1
    end
    ready = submitted && events.find { |e| e.event == 'generation_ready' && e.kind == 'supplement' && e.occurred_at >= submitted }
    b[:supplement_durations] << (ready.occurred_at - submitted) if ready
  end

  def finalize(bucket)
    durations = bucket.delete(:durations).sort
    supplement = bucket.delete(:supplement_durations)
    bucket.merge(duration_samples: durations.length,
      average_seconds: durations.any? ? (durations.sum / durations.length).round(1) : nil,
      median_seconds: durations.any? ? ((durations[(durations.length - 1) / 2] + durations[durations.length / 2]) / 2.0).round(1) : nil,
      p95_seconds: durations.any? ? durations[(durations.length * 0.95).ceil - 1].round(1) : nil,
      supplement_average_seconds: supplement.any? ? (supplement.sum / supplement.length).round(1) : nil)
  end

  def collect_alerts
    runs = EssayGenerationRun.joins(essay_grading: :essay_assignment)
      .where.not(essay_assignments: { category: EssayAssignment.categories.fetch('listening') })
      .where(state: %w[failed unknown queued retry_wait running checking])
    stale = runs.where("COALESCE(CASE WHEN essay_generation_runs.state IN ('running', 'checking') THEN essay_generation_runs.started_at WHEN essay_generation_runs.state = 'retry_wait' THEN essay_generation_runs.next_retry_at END, essay_generation_runs.queued_at, essay_generation_runs.created_at) < ?", @now - WARNING_AGE)
    attention_ids = runs.where(state: %w[failed unknown]).or(stale).select(:essay_grading_id)
    scope = base.where(status: :stopped).or(base.where(status: :pending).where('essay_gradings.created_at < ?', @now - WARNING_AGE))
      .or(base.where(id: attention_ids))
    candidates = bounded(with_context(scope.order('essay_gradings.created_at ASC')), '跨時段异常清單')
    history = event_groups(candidates.map(&:id))
    states = runs.where(essay_grading_id: candidates.map(&:id)).group_by(&:essay_grading_id)
    candidates.filter_map do |g|
      rows = states[g.id] || []
      run = rows.find { |r| r.state == 'unknown' } || rows.find { |r| r.state == 'failed' } || rows.find { |r| run_waiting_since(r) < @now - WARNING_AGE } || rows.first
      last_pending = (history[g.id] || []).reverse.find { |e| e.event == 'pending' }&.occurred_at || g.created_at
      last_pending = run_waiting_since(run) if run && EssayGenerationRun::ACTIVE_STATES.include?(run.state)
      reason = if run&.state == 'unknown'
                 '結果不明，需人工確認'
               elsif g.stopped?
                 '批改已停止'
               elsif run&.kind == 'supplement' && run.state == 'failed'
                 '補充練習失敗（主批改保留）'
               elsif run&.kind == 'supplement' && last_pending < @now - WARNING_AGE
                 '補充練習超過 2 小時，需確認處理狀態'
               elsif g.pending? && last_pending < @now - WARNING_AGE
                 'Pending 超過 2 小時，疑似卡住'
               end
      next unless reason
      error_event = (history[g.id] || []).reverse.find { |e| e.event == 'error' }
      { reason: reason, school: submission_school(g).last, title: g.essay_assignment.title,
        id: g.id, status: g.status, generation_state: run&.state, attempts: run&.attempts,
        failure_stage: error_event&.kind,
        waiting_since: (g.pending? || run&.kind == 'supplement') ? last_pending.iso8601 : nil,
        action: '先查看錯誤／queue／worker／Dify 狀態；確認沒有在跑後再決定是否重試。',
        url: assignment_url(g.essay_assignment_id), grading_url: "https://aienglish.docai.net/essay/grading/#{g.id}" }
    end
  end

  def run_waiting_since(run)
    case run.state
    when 'running', 'checking' then run.started_at || run.queued_at || run.created_at
    when 'retry_wait' then run.next_retry_at || run.queued_at || run.created_at
    else run.queued_at || run.created_at
    end
  end

  def notification_alerts
    eligible = EssayGenerationRun.where(essay_grading_id: base.select(:id))
    deliveries = EssayGenerationNotification.where(essay_generation_run_id: eligible.select(:id))
    problems = deliveries.where(state: %w[unknown build_failed])
      .or(deliveries.where(state: 'delivering').where('claimed_at < ?', @now - 15.minutes))
      .or(deliveries.where(state: 'preparing').where('created_at < ?', @now - 15.minutes))
    rows = problems.includes(essay_generation_run: :essay_grading).order(:created_at).limit(20).map do |delivery|
      grading = delivery.essay_generation_run.essay_grading
      { reason: '錯誤通知郵件未確認寄達', title: grading.topic, id: grading.id,
        action: '請工程師核對郵件傳送紀錄；結果不明時不要直接重寄。', url: assignment_url(grading.essay_assignment_id) }
    end
    # A crash between the database commit and Redis enqueue must not silently
    # consume the notification. Surface it without risking duplicate SMTP sends.
    missing = eligible.where(state: 'failed', notified_at: nil).or(eligible.where(state: 'unknown', attention_notified_at: nil).where.not(attention_required_at: nil))
      .where('essay_generation_runs.updated_at < ?', @now - 15.minutes)
    missing.limit(20).includes(:essay_grading).each do |run|
      next if EssayGenerationNotification.exists?(essay_generation_run_id: run.id, token: run.token)
      rows << { reason: '錯誤通知尚未送出', title: run.essay_grading.topic, id: run.essay_grading_id,
        action: '請工程師核對通知工作是否已入隊。', url: assignment_url(run.essay_grading.essay_assignment_id) }
    end
    @warnings << '錯誤通知寄送問題過多，請工程師核對完整寄送紀錄。' if problems.count > 20 || missing.count > 20
    rows
  end

  def assignment_url(id)
    "https://aienglish-admin.docai.net/submissions?assignmentId=#{id}"
  end
end
