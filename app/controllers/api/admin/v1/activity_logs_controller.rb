# frozen_string_literal: true

module Api
  module Admin
    module V1
      class ActivityLogsController < AdminApiController
        include AdminAuthenticator

        before_action :set_general_user, only: [:index], if: -> { params[:general_user_id].present? }

        # GET /api/admin/v1/activity_logs
        def index
          # 初始查詢
          @events = Ahoy::Event.all.order(time: :desc)
          @events = @events.page(params[:page] || 1)

          render json: { success: true, events: @events, meta: pagination_meta(@events) }, status: :ok
        end

        # GET /api/admin/v1/general_users/:general_user_id/activity_logs
        def show_by_general_user
          @events = Ahoy::Event.where(user_id: params[:id]).order(time: :desc)
          @events = @events.page(params[:page] || 1)

          render json: { success: true, events: @events, meta: pagination_meta(@events) }, status: :ok
        end

        private

        def set_general_user
          @general_user = GeneralUser.find(params[:general_user_id])
        rescue ActiveRecord::RecordNotFound
          render json: { success: false, error: { message: 'User not found' } }, status: :not_found
        end

        def format_events(events)
          events.map do |event|
            {
              id: event.id,
              event_type: event.name,
              time: event.time,
              user: if event.general_user.present?
                      {
                        id: event.general_user.id,
                        email: event.general_user.email,
                        name: event.general_user.try(:full_name) || event.general_user.email.split('@').first
                      }
                    end,
              properties: event.properties,
              visit_info: if event.visit.present?
                            {
                              ip: event.visit.ip,
                              user_agent: event.visit.user_agent,
                              browser: event.visit.browser,
                              os: event.visit.os,
                              device_type: event.visit.device_type,
                              started_at: event.visit.started_at
                            }
                          end
            }
          end
        end

        def pagination_meta(object)
          {
            current_page: object.current_page,
            next_page: object.next_page,
            prev_page: object.prev_page,
            total_pages: object.total_pages,
            total_count: object.total_count
          }
        end
      end
    end
  end
end
