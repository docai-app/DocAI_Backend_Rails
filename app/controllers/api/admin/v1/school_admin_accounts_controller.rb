# frozen_string_literal: true

module Api
  module Admin
    module V1
      class SchoolAdminAccountsController < AdminApiController
        include AdminAuthenticator

        def index
          scope = GeneralUser.school_admins.includes(:school)
          scope = scope.where(school_id: params[:school_id]) if params[:school_id].present?

          page = params[:page] || 1
          per_page = (params[:per_page] || 30).to_i.clamp(1, 100)
          users = scope.order(created_at: :desc).page(page).per(per_page)

          rows = users.map { |u| account_json(u) }

          render json: {
            success: true,
            data: {
              accounts: rows,
              pagination: pagination_meta(users)
            }
          }, status: :ok
        end

        def create
          school = School.find(params.require(:school_id))
          email = params.require(:email).to_s.strip.downcase
          password = params.require(:password)

          user = GeneralUser.new(
            email: email,
            password: password,
            nickname: params[:nickname].presence || email.split('@').first,
            school_id: school.id,
            meta: {
              'aienglish_role' => SchoolPortal::AIENGLISH_ROLE_SCHOOL_ADMIN,
              'aienglish_features_list' => []
            },
            konnecai_tokens: {}
          )

          ActiveRecord::Base.transaction do
            user.save!
            user.create_energy(value: 100) unless user.energy
          end

          render json: { success: true, data: { account: account_json(user) } }, status: :created
        rescue ActiveRecord::RecordInvalid => e
          render json: { success: false, errors: e.record.errors.full_messages }, status: :unprocessable_entity
        rescue ActiveRecord::RecordNotFound
          render json: { success: false, error: 'School not found' }, status: :not_found
        end

        def toggle_status
          user = GeneralUser.school_admins.find(params[:id])
          if user.locked_at.present?
            user.update!(locked_at: nil, failed_attempts: 0, unlock_token: nil)
            active = true
          else
            user.update!(locked_at: Time.current)
            active = false
          end

          render json: { success: true, data: { account: account_json(user), active: active } }, status: :ok
        rescue ActiveRecord::RecordNotFound
          render json: { success: false, error: 'Account not found' }, status: :not_found
        end

        private

        def account_json(user)
          {
            id: user.id,
            email: user.email,
            nickname: user.nickname,
            school_id: user.school_id,
            locked_at: user.locked_at,
            active: user.locked_at.blank?,
            created_at: user.created_at
          }
        end

        def pagination_meta(collection)
          {
            current_page: collection.current_page,
            next_page: collection.next_page,
            prev_page: collection.prev_page,
            total_pages: collection.total_pages,
            total_count: collection.total_count
          }
        end
      end
    end
  end
end
