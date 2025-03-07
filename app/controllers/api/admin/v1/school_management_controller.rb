# frozen_string_literal: true

module Api
  module V1
    module Admin
      class SchoolManagementController < AdminApiController
        before_action :authenticate_admin_user!
        before_action :set_school,
                      only: %i[show update student_stats teacher_stats assign_students assign_teachers]

        include SchoolConstants # 引入之前定義的常量

        # GET /api/v1/admin/schools
        def index
          @schools = School.all
          render json: {
            status: 'success',
            data: @schools.map { |school| school_data(school) }
          }
        end

        # GET /api/v1/admin/schools/:code
        def show
          render json: {
            status: 'success',
            data: school_data(@school)
          }
        end

        # POST /api/v1/admin/schools
        def create
          school_creator = SchoolCreator.new(school_params)

          if school_creator.create
            render json: {
              status: 'success',
              data: school_data(school_creator.school),
              message: "成功創建學校: #{school_creator.school.name}"
            }
          else
            render json: {
              status: 'error',
              message: school_creator.errors.full_messages
            }, status: :unprocessable_entity
          end
        end

        # POST /api/v1/admin/schools/:code/assign_students
        def assign_students
          assigner = StudentAssigner.new(
            school: @school,
            academic_year_name: params[:academic_year_name],
            email_patterns: params[:email_patterns]
          )

          if assigner.assign
            render json: {
              status: 'success',
              message: '學生分配成功',
              data: {
                assigned_count: assigner.assigned_count,
                skipped_count: assigner.skipped_count
              }
            }
          else
            render json: {
              status: 'error',
              message: assigner.errors.full_messages
            }, status: :unprocessable_entity
          end
        end

        # POST /api/v1/admin/schools/:code/assign_teachers
        def assign_teachers
          assigner = TeacherAssigner.new(
            school: @school,
            academic_year_name: params[:academic_year_name],
            email_patterns: params[:email_patterns],
            department: params[:department],
            position: params[:position]
          )

          if assigner.assign
            render json: {
              status: 'success',
              message: '教師分配成功',
              data: {
                assigned_count: assigner.assigned_count,
                skipped_count: assigner.skipped_count
              }
            }
          else
            render json: {
              status: 'error',
              message: assigner.errors.full_messages
            }, status: :unprocessable_entity
          end
        end

        # GET /api/v1/admin/schools/:code/student_stats
        def student_stats
          stats = StudentStatsGenerator.new(@school)
          render json: {
            status: 'success',
            data: stats.generate
          }
        end

        # GET /api/v1/admin/schools/:code/teacher_stats
        def teacher_stats
          stats = TeacherStatsGenerator.new(@school)
          render json: {
            status: 'success',
            data: stats.generate
          }
        end

        private

        def set_school
          @school = School.find_by!(code: params[:code])
        rescue ActiveRecord::RecordNotFound
          render json: {
            status: 'error',
            message: "找不到學校代碼: #{params[:code]}"
          }, status: :not_found
        end

        def school_params
          params.require(:school).permit(
            :name, :code, :status, :address,
            :contact_email, :contact_phone,
            :region, :timezone,
            :school_type, :curriculum_type,
            :academic_system,
            academic_years: %i[name status start_year start_month end_month],
            custom_settings: {}
          )
        end

        def school_data(school)
          {
            id: school.id,
            name: school.name,
            code: school.code,
            status: school.status,
            address: school.address,
            contact_email: school.contact_email,
            contact_phone: school.contact_phone,
            timezone: school.timezone,
            meta: school.meta,
            academic_years: school.school_academic_years.map do |year|
              {
                name: year.name,
                status: year.status,
                start_date: year.start_date,
                end_date: year.end_date
              }
            end
          }
        end
      end
    end
  end
end
