# frozen_string_literal: true

require 'csv'

module Api
  module Admin
    module V1
      class GeneralUsersController < AdminApiController
        include AdminAuthenticator

        def index
          @users = GeneralUser.all.order(created_at: :desc).as_json(except: %i[aienglish_feature_list])
          @users = Kaminari.paginate_array(@users).page(params[:page])
          render json: { success: true, users: @users, meta: pagination_meta(@users) }, status: :ok
        rescue StandardError => e
          render json: { success: false, error: e.message }, status: :internal_server_error
        end

        def show
          @user = GeneralUser.find(params[:id])
          render json: { success: true, user: @user }, status: :ok
        rescue StandardError => e
          render json: { success: false, error: e.message }, status: :internal_server_error
        end

        def create
          @user = GeneralUser.new(general_users_params)

          if @user.save
            @user.create_energy(value: 100)

            if params[:aienglish_features].present?
              features = Array(params[:aienglish_features])
              @user.aienglish_feature_list.add(*features)
              @user.save
            end

            render json: { success: true, user: @user }, status: :ok
          else
            render json: { success: false, errors: @user.errors.full_messages }, status: :unprocessable_entity
          end
        rescue StandardError => e
          render json: { success: false, error: e.message }, status: :internal_server_error
        end

        def update
          @user = GeneralUser.find(params[:id])

          if @user.update(general_users_params)
            if params[:aienglish_features].present?
              features = Array(params[:aienglish_features])
              @user.aienglish_feature_list = features
              @user.save
            end

            render json: { success: true, user: @user }, status: :ok
          else
            render json: { success: false, errors: @user.errors.full_messages }, status: :unprocessable_entity
          end
        rescue ActiveRecord::RecordNotFound
          render json: { success: false, error: 'User not found' }, status: :not_found
        rescue StandardError => e
          render json: { success: false, error: e.message }, status: :internal_server_error
        end

        def batch_create
          file = params[:file]

          return render json: { success: false, error: 'File not found' }, status: :bad_request if file.nil?

          @users = []
          errors = []

          CSV.foreach(file.path, headers: true) do |row|
            ActiveRecord::Base.transaction do
              email = row['email']&.strip
              password = row['password']&.strip
              nickname = row['name']&.strip.to_s
              banbie = row['class_name']&.strip.to_s
              class_no = row['class_no']&.strip.to_s

              @user = GeneralUser.create!(
                email:,
                password:,
                nickname:,
                banbie:,
                class_no:
              )
              @user.create_energy(value: 100)

              if row['aienglish_features'].present?
                features = begin
                  JSON.parse(row['aienglish_features'])
                rescue StandardError
                  []
                end
                @user.aienglish_feature_list.add(*features)
                @user.save!
              end

              @users << @user
              puts "Imported #{email} successfully."
            end
          rescue StandardError => e
            errors << { email: email || 'N/A', error: e.message }
            puts "Failed to import #{email || 'N/A'}: #{e.message}"
          end

          if errors.empty?
            render json: { success: true, users: @users }, status: :created
          else
            render json: { success: false, errors: }, status: :unprocessable_entity
          end
        end

        private

        def general_users_params
          params.permit(:email, :password, :nickname, :phone, :banbie, :class_no)
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
