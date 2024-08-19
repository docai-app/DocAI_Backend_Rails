# frozen_string_literal: true

require 'csv'

module Api
  module Admin
    module V1
      class GeneralUsersController < AdminApiController
        include AdminAuthenticator

        def index
          @users = GeneralUser.all.page(params[:page])
          render json: { success: true, users: @users, meta: pagination_meta(@users) }, status: :ok
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

        def batch_create
          file = params[:file]

          render json: { success: false, error: 'File not found' }, status: :bad_request if file.nil?

          @users = []

          CSV.foreach(file, headers: true) do |row|
            @user = GeneralUser.create!(
              email: row['email'],
              password: row['password'],
              nickname: "#{row['name']} #{row['class']}"
            )
            @user.create_energy(value: 100)
            puts "Imported #{row['email']} successfully."
            @users << @user
          rescue StandardError => e
            puts "Failed to import #{row['email']}: #{e.message}"
            render json: { success: false, error: e.message }, status: :internal_server_error
          end

          render json: { success: true, users: @users }, status: :created
        rescue StandardError => e
          render json: { success: false, error: e.message }, status: :internal_server_error
        end

        private

        def general_users_params
          params.permit(:email, :password, :nickname, :phone)
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
