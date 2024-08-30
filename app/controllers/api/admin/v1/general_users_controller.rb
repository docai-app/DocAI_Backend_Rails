# frozen_string_literal: true

require 'csv'

module Api
  module Admin
    module V1
      class GeneralUsersController < AdminApiController
        include AdminAuthenticator

        def index
          @users = GeneralUser.includes([:taggings]).order(created_at: :desc).as_json(methods: [:locked_at],
                                                                                      except: %i[aienglish_feature_list])
          @users = Kaminari.paginate_array(@users).page(params[:page])

          render json: { success: true, users: @users, meta: pagination_meta(@users) }, status: :ok
        rescue StandardError => e
          render json: { success: false, error: e.message }, status: :internal_server_error
        end

        def show
          @user = GeneralUser.find(params[:id])
          user_json = @user.as_json(
            methods: [:locked_at]
          )
          user_json['role'] = @user.has_role?(:teacher) ? 'teacher' : 'student'

          render json: { success: true, user: user_json }, status: :ok
        rescue StandardError => e
          render json: { success: false, error: e.message }, status: :internal_server_error
        end

        def show_students
          @user = GeneralUser.find(params[:id])
          @students = @user.linkable_relation('student').order(created_at: :desc)
          @students = Kaminari.paginate_array(@students).page(params[:page])
          render json: { success: true, teacher: @user, students: @students, meta: pagination_meta(@students) },
                 status: :ok
        rescue StandardError => e
          render json: { success: false, error: e.message }, status: :internal_server_error
        end

        def show_teachers
          @user = GeneralUser.find(params[:id])
          @teachers = @user.find_teachers_via_students
          @teachers = Kaminari.paginate_array(@teachers).page(params[:page])
          render json: { success: true, student: @user, teachers: @teachers }, status: :ok
        rescue StandardError => e
          render json: { success: false, error: e.message }, status: :internal_server_error
        end

        def create
          @user = GeneralUser.new(general_users_params)

          if @user.save
            @user.create_energy(value: 100)

            if params[:aienglish_features].present?
              features = Utils.array_to_tag_string(params[:aienglish_features])
              @user.aienglish_feature_list.add(*features)
              @user.save
            end

            if params[:role].present?
              @user.add_role(params[:role])
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
            @user.reload
            if params[:aienglish_features].present?
              features = Utils.array_to_tag_string(params[:aienglish_features])
              current_features = Utils.array_to_tag_string(@user.aienglish_feature_list)
              @user.aienglish_feature_list.remove(current_features, parse: true)
              @user.aienglish_feature_list.add(features, parse: true)
              @user.save
              @user.reload
            end

            if params[:role].present?
              @user.remove_role(:student)
              @user.remove_role(:teacher)
              @user.add_role(params[:role])
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

        def update_password
          @user = GeneralUser.find(params[:id])

          if @user.update(password: params[:password])
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

              if row['role'].present?
                @user.add_role(row['role'])
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

        def lock_user
          @user = GeneralUser.find(params[:id])
          if @user.update(locked_at: Time.current)
            render json: { success: true, user: @user }, status: :ok
          else
            render json: { success: false, error: 'User not found' }, status: :not_found
          end
        rescue StandardError => e
          render json: { success: false, error: e.message }, status: :internal_server_error
        end

        def unlock_user
          @user = GeneralUser.find(params[:id])
          if @user.update(locked_at: nil, failed_attempts: 0, unlock_token: nil)
            render json: { success: true, user: @user }, status: :ok
          else
            render json: { success: false, error: 'User not found' }, status: :not_found
          end
        rescue StandardError => e
          render json: { success: false, error: e.message }, status: :internal_server_error
        end

        def add_students_relation_by_emails
          @teacher = GeneralUser.find_by(email: params[:teacher_email])
          @students = GeneralUser.where(email: params[:student_emails])

          @students.each do |student|
            KgLinker.add_student_relation(teacher: @teacher, student:)
          end

          render json: { success: true, teacher: @teacher, students: @students }, status: :ok
        rescue StandardError => e
          render json: { success: false, message: e.message }, status: :internal_server_error
        end

        def batch_students_relation_by_emails
          file = params[:file]

          return render json: { success: false, error: 'File not found' }, status: :bad_request if file.nil?

          @teacher = []
          @students = []
          errors = []

          CSV.foreach(file.path, headers: true) do |row|
            ActiveRecord::Base.transaction do
              teacher_email = row['teacher_email']&.strip

              student_emails = begin
                JSON.parse(row['student_emails'])
              rescue StandardError
                []
              end

              @teacher = GeneralUser.find_by(email: teacher_email)
              @students = GeneralUser.where(email: student_emails)

              @students.each do |student|
                KgLinker.add_student_relation(teacher: @teacher, student:)
              end
            end
          rescue StandardError => e
            errors << { email: email || 'N/A', error: e.message }
          end

          render json: { success: true, message: 'Done' }, status: :ok
        rescue StandardError => e
          render json: { success: false, message: e.message, errors: }, status: :internal_server_error
        end

        private

        def general_users_params
          params.permit(:email, :password, :nickname, :phone, :banbie, :class_no, :role)
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
