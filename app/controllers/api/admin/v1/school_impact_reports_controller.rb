# frozen_string_literal: true

module Api
  module Admin
    module V1
      class SchoolImpactReportsController < AdminApiController
        # GET /api/admin/v1/school-impact-report?school_id=UUID&start_date=YYYY-MM-DD&end_date=YYYY-MM-DD
        def show
          school_id = params[:school_id].to_s
          start_date = params[:start_date].to_s
          end_date = params[:end_date].to_s
          class_limit = params[:class_limit].present? ? params[:class_limit].to_i : nil

          if school_id.blank? || start_date.blank? || end_date.blank?
            render json: { status: 'error', code: 422, message: 'school_id, start_date, end_date are required' },
                   status: :unprocessable_entity
            return
          end

          payload = Schools::SchoolImpactReportGenerator.new(
            school_id: school_id,
            start_date: start_date,
            end_date: end_date,
            class_limit: class_limit
          ).generate

          render json: {
            status: 'success',
            code: 200,
            data: payload,
            meta: {
              generated_at: Time.current.iso8601,
              filtered_by: {
                school_id: school_id,
                start_date: start_date,
                end_date: end_date
              }
            }
          }
        rescue ArgumentError => e
          render json: { status: 'error', code: 422, message: e.message }, status: :unprocessable_entity
        rescue ActiveRecord::RecordNotFound
          render json: { status: 'error', code: 404, message: 'School not found' }, status: :not_found
        rescue StandardError => e
          Rails.logger.error("[SchoolImpactReports#show] #{e.class}: #{e.message}")
          Rails.logger.error(e.backtrace.join("\n"))
          render json: { status: 'error', code: 500, message: 'Internal server error' },
                 status: :internal_server_error
        end
      end
    end
  end
end

