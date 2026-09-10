# frozen_string_literal: true

# Real QG HTTP + Azure reads, in-process Rails API requests; not browser proof.
raise 'Isolated test required' unless Rails.env.test? && ENV['LISTENING_RAILS_ISOLATED_TEST'] == '1'
raise 'Unexpected DB' unless ActiveRecord::Base.connection.select_value('select current_database()') == 'listening_rails_isolated_test'
raise 'Only --prepare-only is supported' unless ARGV.empty? || ARGV == ['--prepare-only']
prepare_only = ARGV == ['--prepare-only']
load Rails.root.join('script/listening_http_seed.rb')
teacher = GeneralUser.find_by!(email: 'listening-http-teacher@example.test')
student = GeneralUser.find_by!(email: 'listening-http-student@example.test')
year = teacher.teacher_assignments.first.school_academic_year
headers_for = lambda do |user|
  login = ActionDispatch::Integration::Session.new(Rails.application)
  login.host!('localhost')
  login.post('/general_users/sign_in', params: { general_user: { email: user.email, password: 'ListeningLocalTest123!' } }, as: :json)
  authorization = login.response.headers['Authorization']
  raise "Login HTTP #{login.response.status}" unless login.response.status == 200 && authorization.to_s.start_with?('Bearer ')
  begin
    Warden::JWTAuth::UserDecoder.new.call(authorization.delete_prefix('Bearer '), :general_user, nil)
  rescue StandardError => error
    raise "Login token validation failed: #{error.class}"
  end
  { 'Authorization' => authorization }
end
session = ActionDispatch::Integration::Session.new(Rails.application)
session.host!('localhost')
check = lambda do |expected, stage|
  raise "#{stage}: HTTP #{session.response.status}" unless session.response.status == expected
end
title = prepare_only ? 'Riverside A2 human acceptance v108' : 'Riverside A2 live assignment v108'
assignment = teacher.essay_assignments.find_by(title: title)
unless assignment
  session.post('/api/v1/essay_assignments', headers: headers_for.call(teacher), as: :json, params: {
    essay_assignment: { category: 'listening', topic: 'Riverside Library', title: title,
      assignment: 'Listen to the library announcement and answer four questions.',
      rubric: { name: 'Listening' }, school_academic_year_id: year.id,
      meta: { listening: { version_id: '108', news_feed_id: '46', level: 'A2', play_limit: 10 } } }
  })
  check.call(201, 'create')
  assignment = EssayAssignment.find(session.response.parsed_body.fetch('essay_assignment').fetch('id'))
end
raise 'Unexpected existing assignment' unless assignment.listening_assignment_snapshot&.qg_version_id == '108'
unless assignment.assigned_to_student?(student)
  session.post("/api/v1/essay_assignments/#{assignment.id}/distributions", headers: headers_for.call(teacher), as: :json,
    params: { distribution: { distribution_type: 'individual', target_student_id: student.id, deadline: 1.week.from_now.iso8601 } })
  check.call(201, 'distribute')
end
if prepare_only
  puts({ success: true, prepared_only: true, assignment_id: assignment.id,
    assignment_code: assignment.code, submissions: assignment.essay_gradings.count }.to_json)
  exit
end
session.get("/api/v1/essay_assignments/#{assignment.id}/listening_content", headers: headers_for.call(student))
check.call(200, 'student content')
content = session.response.parsed_body.fetch('data')
raise 'Answer disclosure' if content.fetch('questions').any? { |q| q.key?('answer') || q.key?('evidence') }
session.post("/api/v1/essay_assignments/#{assignment.id}/listening_audio", headers: headers_for.call(student), as: :json,
  params: { request_id: 'riverside-a2-v108-live-play-0001' })
check.call(200, 'private audio')
snapshot = assignment.listening_assignment_snapshot
raise 'Audio mismatch' unless Digest::SHA256.hexdigest(session.response.body) == snapshot.audio_metadata.fetch('sha256')
answers = snapshot.quiz.fetch('questions').fetch('multiple_choice').map { |q| { id: q.fetch('id'), user_answer: q.fetch('answer') } }
session.post("/api/v1/essay_assignments/#{assignment.code}/essay_gradings", headers: headers_for.call(student).merge('Idempotency-Key' => 'riverside-a2-v108-live-submit-0001'), as: :json,
  params: { essay_grading: { status: 'pending', grading: { listening: { questions: answers } } } })
raise "Submit HTTP #{session.response.status}" unless [200, 201].include?(session.response.status)
grading = session.response.parsed_body.fetch('essay_grading')
raise 'Grading mismatch' unless grading['status'] == 'graded' && grading.dig('grading', 'listening', 'score') == 4
puts({ success: true, assignment_id: assignment.id, assignment_code: assignment.code,
  qg_version_id: snapshot.qg_version_id, questions: content.fetch('questions').size,
  audio_sha256_verified: true, graded_score: 4, grading_id: grading['id'] }.to_json)
