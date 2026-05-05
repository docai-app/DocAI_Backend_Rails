# frozen_string_literal: true

module Api
  module School
    module V1
      class StudentsController < SchoolApiController
        def index
          scope = students_scope
          scope = scope.merge(GeneralUser.search_query(params[:keyword])) if params[:keyword].present?
          scope = scope.order(updated_at: :desc)

          page = params[:page] || 1
          per_page = (params[:per_page] || 20).to_i.clamp(1, 100)
          students = scope.page(page).per(per_page)

          rows = students.map { |u| student_json(u) }

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

          render json: { success: true, data: { student: student_json(student) } }, status: :ok
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

        def student_json(user)
          {
            id: user.id,
            student_name: user.nickname,
            email: user.email,
            class_name: user.banbie,
            student_number: user.class_no,
            status: user.locked_at.present? ? 'locked' : 'active',
            updated_at: user.updated_at
          }
        end
      end
    end
  end
end
