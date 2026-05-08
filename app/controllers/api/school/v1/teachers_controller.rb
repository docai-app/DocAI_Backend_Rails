# frozen_string_literal: true

module Api
  module School
    module V1
      class TeachersController < SchoolApiController
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
                teachers: [],
                pagination: empty_pagination
              }
            }, status: :ok
          end

          scope = teachers_scope_for_year(academic_year)
          scope = scope.merge(GeneralUser.search_query(params[:keyword])) if params[:keyword].present?

          if params[:email].present?
            term = "%#{ActiveRecord::Base.sanitize_sql_like(params[:email].to_s.downcase)}%"
            scope = scope.where('LOWER(general_users.email) LIKE ?', term)
          end

          if params[:name].present?
            term = "%#{ActiveRecord::Base.sanitize_sql_like(params[:name].to_s.downcase)}%"
            scope = scope.where('LOWER(general_users.nickname) LIKE ?', term)
          end

          scope = scope.distinct.order('general_users.updated_at DESC')

          page = params[:page] || 1
          per_page = (params[:per_page] || 20).to_i.clamp(1, 100)
          teachers = scope.includes(:teacher_assignments).page(page).per(per_page)

          rows = teachers.map { |u| teacher_json(u, academic_year: academic_year) }.compact

          render json: {
            success: true,
            data: {
              teachers: rows,
              pagination: pagination_meta(teachers)
            }
          }, status: :ok
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

        def teachers_scope_for_year(academic_year)
          GeneralUser.joins(teacher_assignments: :school_academic_year)
                     .where(school_academic_years: { school_id: current_school.id })
                     .where(teacher_assignments: { school_academic_year_id: academic_year.id })
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

        def teacher_json(user, academic_year:)
          assignment = user.teacher_assignments.find { |ta| ta.school_academic_year_id == academic_year.id }
          return unless assignment

          {
            id: user.id,
            teacher_name: user.nickname,
            email: user.email,
            department: assignment.department,
            position: assignment.position,
            assignment_status: assignment.status,
            updated_at: user.updated_at
          }
        end
      end
    end
  end
end
