# frozen_string_literal: true

module Api
  module School
    module V1
      class StudentsController < SchoolApiController
        def index
          if invalid_academic_year_param?
            return render json: {
              success: false,
              error: '學年不存在或不屬於本校'
            }, status: :not_found
          end

          academic_year = resolve_academic_year_for_list
          unless academic_year
            return render json: {
              success: true,
              data: {
                students: [],
                pagination: empty_pagination
              }
            }, status: :ok
          end

          scope = students_scope.where(student_enrollments: { school_academic_year_id: academic_year.id })
          scope = scope.merge(GeneralUser.search_query(params[:keyword])) if params[:keyword].present?
          if params[:class_name].present?
            term = "%#{ActiveRecord::Base.sanitize_sql_like(params[:class_name].to_s)}%"
            scope = scope.where(
              'student_enrollments.class_name ILIKE ? OR general_users.banbie ILIKE ?',
              term,
              term
            )
          end
          if params[:class_no].present?
            term = "%#{ActiveRecord::Base.sanitize_sql_like(params[:class_no].to_s)}%"
            scope = scope.where(
              'student_enrollments.class_number ILIKE ? OR general_users.class_no ILIKE ?',
              term,
              term
            )
          end
          scope = scope.distinct.order(updated_at: :desc)

          page = params[:page] || 1
          per_page = (params[:per_page] || 20).to_i.clamp(1, 100)
          students = scope.includes(:student_enrollments).page(page).per(per_page)

          rows = students.map { |u| student_json(u, academic_year: academic_year) }

          render json: {
            success: true,
            data: {
              students: rows,
              pagination: pagination_meta(students)
            }
          }, status: :ok
        end

        def show
          student = students_scope.find_by(id: params[:id])
          unless student
            return render json: { success: false, error: 'Student not found' }, status: :not_found
          end

          SchoolPortal::AuditLogger.log!(
            actor: current_general_user,
            school: current_school,
            action: 'student_viewed',
            target: student,
            request: request
          )

          academic_year = resolve_academic_year_for_detail
          payload =
            if academic_year
              student_json(student, academic_year: academic_year)
            else
              student_json_without_year(student)
            end

          render json: {
            success: true,
            data: { student: payload }
          }, status: :ok
        end

        def reset_password
          student = students_scope.find_by(id: params[:id])
          unless student
            return render json: { success: false, error: 'Student not found' }, status: :not_found
          end

          student.password = SchoolPortal::DEFAULT_STUDENT_RESET_PASSWORD
          unless student.save
            return render json: { success: false, errors: student.errors.full_messages }, status: :unprocessable_entity
          end

          SchoolPortal::AuditLogger.log!(
            actor: current_general_user,
            school: current_school,
            action: 'student_password_reset',
            target: student,
            metadata: {
              reset_to_default_password: true,
              default_password_label: SchoolPortal::DEFAULT_STUDENT_RESET_PASSWORD
            },
            request: request
          )

          render json: { success: true, message: 'Password reset.' }, status: :ok
        end

        private

        def invalid_academic_year_param?
          params[:school_academic_year_id].present? &&
            current_school.school_academic_years.find_by(id: params[:school_academic_year_id]).nil?
        end

        def resolve_academic_year_for_list
          if params[:school_academic_year_id].present?
            current_school.school_academic_years.find_by(id: params[:school_academic_year_id])
          else
            current_school.school_academic_years.find_by(status: :active) ||
              current_school.school_academic_years.order(start_date: :desc).first
          end
        end

        def resolve_academic_year_for_detail
          if params[:school_academic_year_id].present?
            current_school.school_academic_years.find_by(id: params[:school_academic_year_id])
          else
            current_school.school_academic_years.find_by(status: :active) ||
              current_school.school_academic_years.order(start_date: :desc).first
          end
        end

        def empty_pagination
          {
            current_page: 1,
            next_page: nil,
            prev_page: nil,
            total_pages: 1,
            total_count: 0
          }
        end

        def student_json(user, academic_year:)
          enrollment =
            user.student_enrollments.find { |e| e.school_academic_year_id == academic_year.id }

          es = enrollment&.status || 'active'

          {
            id: user.id,
            student_name: user.nickname,
            email: user.email,
            class_name: enrollment&.class_name.presence || user.banbie,
            student_number: enrollment&.class_number.presence || user.class_no,
            enrollment_status: es,
            updated_at: user.updated_at
          }
        end

        def student_json_without_year(user)
          {
            id: user.id,
            student_name: user.nickname,
            email: user.email,
            class_name: user.banbie,
            student_number: user.class_no,
            enrollment_status: 'active',
            updated_at: user.updated_at
          }
        end
      end
    end
  end
end
