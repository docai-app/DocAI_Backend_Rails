# frozen_string_literal: true

require 'test_helper'

module Api
  module V1
    class EssayAssignmentsControllerTest < ActionDispatch::IntegrationTest
      include Devise::Test::IntegrationHelpers

      self.fixture_table_names = []

      setup do
        host! 'docai-dev.m2mda.com'
        @school = create_school!('Assignment Create School')
        @current_year = create_year!(@school, '2026-2027', :active)
        @past_year = create_year!(@school, '2025-2026', :archived)
        @teacher = create_teacher!('assignment-create-teacher')
        assign_teacher_to!(@teacher, @current_year)
        assign_teacher_to!(@teacher, @past_year)
        sign_in @teacher
      end

      test 'stores the explicitly selected academic year when creating an assignment' do
        post '/api/v1/essay_assignments.json',
             params: assignment_params(@past_year.id),
             as: :json

        assert_response :created, response.body
        assert_equal 1, ::EssayAssignment.where(general_user: @teacher).count
        assert_equal @past_year.id, ::EssayAssignment.order(:created_at).last.school_academic_year_id
      end

      test 'defaults to the active academic year for an older client' do
        post '/api/v1/essay_assignments.json', params: assignment_params, as: :json

        assert_response :created, response.body
        assert_equal 1, ::EssayAssignment.where(general_user: @teacher).count
        assert_equal @current_year.id, ::EssayAssignment.order(:created_at).last.school_academic_year_id
      end

      test 'creates an essay with scores hidden for later release' do
        post '/api/v1/essay_assignments.json',
             params: assignment_params(@current_year.id, meta: { score_visible: false }),
             as: :json

        assert_response :created, response.body
        assignment = ::EssayAssignment.order(:created_at).last
        assert_equal false, assignment.meta['score_visible']
        assert_not assignment.scores_released?
      end

      test 'creates an essay with scores visible immediately when selected' do
        post '/api/v1/essay_assignments.json',
             params: assignment_params(@current_year.id, meta: { score_visible: true }),
             as: :json

        assert_response :created, response.body
        assignment = ::EssayAssignment.order(:created_at).last
        assert_equal true, assignment.meta['score_visible']
        assert assignment.scores_released?
      end

      test 'lists a newly created assignment by its stored academic year instead of its creation date' do
        post '/api/v1/essay_assignments.json', params: assignment_params(@past_year.id), as: :json

        assert_response :created, response.body
        assignment_id = response.parsed_body.dig('essay_assignment', 'id')

        get '/api/v1/essay_assignments.json',
            params: { school_academic_year_id: @current_year.id },
            as: :json

        assert_response :ok, response.body
        assert_not_includes listed_assignment_ids, assignment_id

        get '/api/v1/essay_assignments.json',
            params: { school_academic_year_id: @past_year.id },
            as: :json

        assert_response :ok, response.body
        assert_includes listed_assignment_ids, assignment_id

        get '/api/v1/essay_assignments.json',
            params: { school_academic_year_id: 'all' },
            as: :json

        assert_response :ok, response.body
        assert_includes listed_assignment_ids, assignment_id
      end

      test 'rejects an academic year that is unavailable to the teacher' do
        other_school = create_school!('Unavailable Assignment School')
        unavailable_year = create_year!(other_school, 'Unavailable Year', :active)

        assert_no_difference('::EssayAssignment.count') do
          post '/api/v1/essay_assignments.json',
               params: assignment_params(unavailable_year.id),
               as: :json
        end

        assert_response :forbidden
      end

      test 'rejects all years as a creation target' do
        assert_no_difference('::EssayAssignment.count') do
          post '/api/v1/essay_assignments.json',
               params: assignment_params('all'),
               as: :json
        end

        assert_response :forbidden
      end

      test 'releases comprehension scores and answers to students' do
        assignment = create_release_assignment!(category: :comprehension)

        patch "/api/v1/essay_assignments/#{assignment.id}/release_scores.json", as: :json

        assert_response :ok, response.body
        assignment.reload
        assert assignment.answer_visible?
        assert assignment.scores_released?
        assert_equal @teacher.id, assignment.meta['score_released_by_id']
        assert assignment.meta['score_released_at'].present?
        assert_equal true, response.parsed_body.dig('score_release', 'released')
      end

      test 'assignment detail exposes score release state and owner capability' do
        assignment = create_release_assignment!(category: :essay)

        get "/api/v1/essay_assignments/#{assignment.id}.json", as: :json

        assert_response :ok, response.body
        assignment_json = response.parsed_body.fetch('essay_assignment')
        assert_equal @current_year.id.to_s, assignment_json['school_academic_year_id'].to_s
        assert_equal true, assignment_json['can_release_scores']
        assert_equal true, assignment_json.dig('score_release', 'supported')
        assert_equal false, assignment_json.dig('score_release', 'released')
        assert_nil assignment_json.dig('score_release', 'released_at')
      end

      test 'shared teacher can view and release scores' do
        assignment = create_release_assignment!(category: :essay)
        shared_teacher = create_teacher!('score-release-shared-teacher')
        assign_teacher_to!(shared_teacher, @current_year)
        create_share!(assignment:, shared_teacher:)
        sign_out @teacher
        sign_in shared_teacher

        get "/api/v1/essay_assignments/#{assignment.id}.json", as: :json

        assert_response :ok, response.body
        assert_equal true,
                     response.parsed_body.dig('essay_assignment', 'can_release_scores')

        patch "/api/v1/essay_assignments/#{assignment.id}/release_scores.json", as: :json

        assert_response :ok, response.body
        assignment.reload
        assert assignment.scores_released?
        assert_equal shared_teacher.id, assignment.meta['score_released_by_id']
      end

      test 'shared teacher without the assignment category feature cannot release scores' do
        assignment = create_release_assignment!(category: :comprehension)
        shared_teacher = create_teacher!('score-release-shared-without-feature')
        assign_teacher_to!(shared_teacher, @current_year)
        create_share!(assignment:, shared_teacher:)
        sign_out @teacher
        sign_in shared_teacher

        get "/api/v1/essay_assignments/#{assignment.id}.json", as: :json

        assert_response :ok, response.body
        assert_equal false,
                     response.parsed_body.dig('essay_assignment', 'can_release_scores')

        patch "/api/v1/essay_assignments/#{assignment.id}/release_scores.json", as: :json

        assert_response :forbidden
        assert_not assignment.reload.scores_released?
      end

      test 'releases essay scores without changing comprehension answer visibility' do
        assignment = create_release_assignment!(
          category: :essay,
          meta: { 'existing_setting' => 'preserved', 'score_visible' => false }
        )

        patch "/api/v1/essay_assignments/#{assignment.id}/release_scores.json", as: :json

        assert_response :ok, response.body
        assignment.reload
        assert_equal false, assignment.answer_visible
        assert_equal true, assignment.meta['score_visible']
        assert_equal 'preserved', assignment.meta['existing_setting']
        assert assignment.scores_released?
      end

      test 'releasing scores is idempotent and preserves the original release timestamp' do
        assignment = create_release_assignment!(category: :essay)

        patch "/api/v1/essay_assignments/#{assignment.id}/release_scores.json", as: :json
        assert_response :ok, response.body
        first_released_at = assignment.reload.score_released_at

        travel 1.minute do
          patch "/api/v1/essay_assignments/#{assignment.id}/release_scores.json", as: :json
        end

        assert_response :ok, response.body
        assert_equal first_released_at, assignment.reload.score_released_at
      end

      test 'rejects score release by a teacher without an active share' do
        assignment = create_release_assignment!(category: :essay)
        other_teacher = create_teacher!('score-release-other-teacher')
        sign_out @teacher
        sign_in other_teacher

        patch "/api/v1/essay_assignments/#{assignment.id}/release_scores.json", as: :json

        assert_response :forbidden
        assert_not assignment.reload.scores_released?
      end

      test 'rejects score release for unsupported assignment categories' do
        assignment = create_release_assignment!(category: :speaking_conversation)

        get "/api/v1/essay_assignments/#{assignment.id}.json", as: :json

        assert_response :ok, response.body
        assert_equal false,
                     response.parsed_body.dig('essay_assignment', 'score_release', 'supported')
        assert_equal false,
                     response.parsed_body.dig('essay_assignment', 'can_release_scores')

        patch "/api/v1/essay_assignments/#{assignment.id}/release_scores.json", as: :json

        assert_response :unprocessable_entity
        assert_equal false, response.parsed_body['success']
      end

      private

      def assignment_params(academic_year_id = nil, meta: {})
        attributes = {
          topic: 'Academic Year Topic',
          assignment: 'Academic Year Assignment',
          title: "Academic Year Assignment #{SecureRandom.hex(4)}",
          category: 'essay',
          rubric: {
            name: 'Test Rubric',
            app_key: { grading: 'grading-key', general_context: 'context-key' }
          },
          meta:
        }
        attributes[:school_academic_year_id] = academic_year_id if academic_year_id

        { essay_assignment: attributes }
      end

      def create_release_assignment!(category:, meta: {})
        ::EssayAssignment.create!(
          general_user: @teacher,
          school_academic_year: @current_year,
          topic: 'Score Release Topic',
          assignment: 'Score Release Assignment',
          title: "Score Release #{SecureRandom.hex(4)}",
          category:,
          answer_visible: false,
          rubric: {
            'name' => 'Test Rubric',
            'app_key' => { 'grading' => 'grading-key', 'general_context' => 'context-key' }
          },
          meta:
        )
      end

      def create_share!(assignment:, shared_teacher:)
        ::EssayAssignmentShare.create!(
          essay_assignment: assignment,
          shared_with_general_user: shared_teacher,
          shared_by_general_user: @teacher,
          school: @school,
          school_academic_year: @current_year,
          status: :active
        )
      end

      def listed_assignment_ids
        response.parsed_body.fetch('essay_assignments').pluck('id')
      end

      def create_school!(name)
        ::School.create!(
          name:,
          code: "#{name.parameterize}-#{SecureRandom.hex(4)}",
          timezone: 'Asia/Hong_Kong',
          meta: {}
        )
      end

      def create_year!(school, name, status)
        year_number = status == :archived ? 2025 : 2026
        ::SchoolAcademicYear.create!(
          school:,
          name:,
          start_date: Date.new(year_number, 8, 1),
          end_date: Date.new(year_number + 1, 7, 31),
          status:,
          meta: {}
        )
      end

      def create_teacher!(prefix)
        ::GeneralUser.create!(
          email: "#{prefix}-#{SecureRandom.hex(4)}@example.test",
          password: 'Password123!',
          nickname: 'Assignment Create Teacher',
          meta: { 'aienglish_role' => 'teacher', 'aienglish_features_list' => ['essay'] },
          konnecai_tokens: {}
        )
      end

      def assign_teacher_to!(teacher, academic_year)
        ::TeacherAssignment.create!(
          general_user: teacher,
          school_academic_year: academic_year,
          department: 'English',
          position: 'Teacher',
          status: :active,
          meta: {}
        )
      end
    end
  end
end
