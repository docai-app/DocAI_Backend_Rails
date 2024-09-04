# frozen_string_literal: true

require 'csv'
require 'bcrypt'

module Api
  module Admin
    module V1
      class GeneralUsersController < AdminApiController
        include AdminAuthenticator

        def index
          @users = GeneralUser.includes([:taggings])
          @users = @users.search_query(params[:keyword]) if params[:keyword].present?
          @users = @users.order(created_at: :desc).as_json(methods: [:locked_at],
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
          ActiveRecord::Base.transaction do
            @user = GeneralUser.create!(general_users_params)

            # 創建energy
            @user.create_energy(value: 100)

            # 添加aienglish_features標籤
            if params[:aienglish_features].present?
              Utils.array_to_tag_string(params[:aienglish_features])
              @user.aienglish_feature_list.add(params[:aienglish_features], parse: true)
            end

            # 添加角色
            @user.add_role(params[:role]) if params[:role].present?

            raise ActiveRecord::RecordInvalid, @user unless @user.save

            # 構建 user_json 並返回
            user_json = @user.as_json
            user_json['role'] = @user.has_role?(:teacher) ? 'teacher' : 'student'
            render json: { success: true, user: user_json }, status: :ok
          end
        rescue ActiveRecord::RecordInvalid => e
          render json: { success: false, errors: e.record.errors.full_messages }, status: :unprocessable_entity
        rescue StandardError => e
          render json: { success: false, error: e.message }, status: :internal_server_error
        end

        def update
          @user = GeneralUser.find(params[:id])

          begin
            ActiveRecord::Base.transaction do
              if params[:aienglish_features].present?
                features = Utils.array_to_tag_string(params[:aienglish_features])
                current_features = Utils.array_to_tag_string(@user.aienglish_feature_list)
                @user.aienglish_feature_list.remove(current_features, parse: true)
                @user.aienglish_feature_list.add(features, parse: true)
              end

              if params[:role].present?
                @user.roles = [] # 清空所有角色
                @user.add_role(params[:role])
              end

              raise ActiveRecord::RecordInvalid, @user unless @user.update(general_users_params)

              user_json = @user.as_json
              user_json['role'] = @user.has_role?(:teacher) ? 'teacher' : 'student'

              render json: { success: true, user: user_json }, status: :ok
            end
          rescue ActiveRecord::RecordNotFound
            render json: { success: false, error: 'User not found' }, status: :not_found
          rescue ActiveRecord::RecordInvalid
            render json: { success: false, errors: @user.errors.full_messages }, status: :unprocessable_entity
          rescue StandardError => e
            render json: { success: false, error: e.message }, status: :internal_server_error
          end
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

          users_data = []
          energy_insert_data = []
          role_insert_data = []
          aienglish_features_data = []
          roles_data = []
          errors = []
          inserted_users = []
          email = nil  # 在方法的开头定义 email 变量

          begin
            CSV.foreach(file.path, headers: true) do |row|
              puts row['email']
              email = row['email']&.strip
              password = row['password']&.strip
              nickname = row['name']&.strip.to_s
              banbie = row['class_name']&.strip.to_s
              class_no = row['class_no']&.strip.to_s

              inserted_users << GeneralUser.create!(
                email: email,
                password: password,
                password_confirmation: password,
                nickname: nickname,
                banbie: banbie,
                class_no: class_no
              )
        
              # 收集角色数据
              roles_data << { email:, role: row['role'] } if row['role'].present?

              # 收集 AI English features 数据
              if row['aienglish_features'].present?
                features = begin
                  JSON.parse(row['aienglish_features'].gsub(/[“”]/, '"'))
                rescue JSON::ParserError
                  []
                end
                aienglish_features_data << { email:, features: }
              end
            end

            # 批量插入用户数据，并获取插入后的用户记录
            # inserted_users = GeneralUser.insert_all(users_data, returning: %w[id email])
        
            inserted_users.each do |user|
              user_id = user['id']
              email = user['email']

              # 批量创建 Energy
              energy_insert_data << {
                user_id:,
                user_type: 'GeneralUser',
                value: 100,
                created_at: Time.now,
                updated_at: Time.now
              }

              # 批量添加角色
              role_row = roles_data.find { |r| r[:email].downcase == email.downcase }
              if role_row.present?
                # 根据角色名称查找角色ID
                role = Role.find_by(name: role_row[:role])
                if role.present?
                  role_insert_data << {
                    general_user_id: user_id,
                    role_id: role.id
                  }
                else
                  errors << { email:, error: "Role '#{role_row[:role]}' not found" }
                end
              end

              # 批量添加 AI English features
              feature_row = aienglish_features_data.find { |f| f[:email].downcase == email.downcase }
              if feature_row.present?
                gu = GeneralUser.find(user_id)
                gu.aienglish_feature_list.add(feature_row[:features], parse: true)
                gu.save
              end
            end

            # binding.pry

            # 批量插入 Energy 数据
            Energy.insert_all(energy_insert_data) if energy_insert_data.any?

            # 批量插入 GeneralUsersRole 数据
            GeneralUsersRole.insert_all(role_insert_data) if role_insert_data.any?
          rescue ActiveRecord::RecordInvalid => e
            errors << { email: email || 'N/A', error: e.record.errors.full_messages.join(', ') }
            puts "Failed to import #{email || 'N/A'}: #{e.record.errors.full_messages.join(', ')}"
          rescue StandardError => e
            errors << { email: email || 'N/A', error: e.message }
            puts "Failed to import #{email || 'N/A'}: #{e.message}"
          end

          if errors.empty?
            render json: { success: true, users: inserted_users }, status: :created
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
