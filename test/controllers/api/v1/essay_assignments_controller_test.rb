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

      private

      def assignment_params(academic_year_id = nil)
        attributes = {
          topic: 'Academic Year Topic',
          assignment: 'Academic Year Assignment',
          title: "Academic Year Assignment #{SecureRandom.hex(4)}",
          category: 'essay',
          rubric: {
            name: 'Test Rubric',
            app_key: { grading: 'grading-key', general_context: 'context-key' }
          },
          meta: {}
        }
        attributes[:school_academic_year_id] = academic_year_id if academic_year_id

        { essay_assignment: attributes }
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
