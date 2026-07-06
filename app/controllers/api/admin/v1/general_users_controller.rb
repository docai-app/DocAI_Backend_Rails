# frozen_string_literal: true

require 'csv'
require 'bcrypt'
require 'set'

module Api
  module Admin
    module V1
      class GeneralUsersController < AdminApiController
        include AdminAuthenticator

        def index
          @users = GeneralUser.all

          # 現有的關鍵字搜尋
          @users = @users.search_query(params[:keyword]) if params[:keyword].present?

          # 修正：基於學校ID篩選
          if params[:school_id].present?
            school_id = params[:school_id]

            # 通過學生註冊關聯獲取用戶ID
            student_ids = GeneralUser.joins(student_enrollments: :school_academic_year)
                                     .where(school_academic_years: { school_id: })
                                     .pluck(:id)

            # 通過教師任教關聯獲取用戶ID
            teacher_ids = GeneralUser.joins(teacher_assignments: :school_academic_year)
                                     .where(school_academic_years: { school_id: })
                                     .pluck(:id)

            # 合併兩組ID（去重）並篩選原始查詢
            @users = @users.where(id: (student_ids + teacher_ids).uniq)
          end

          # 修正：基於班級學號篩選
          if params[:class_no].present?
            class_no = params[:class_no]
            # 分別獲取兩組用戶ID並合併
            direct_users_ids = GeneralUser.where(class_no:).pluck(:id)
            enrolled_class_users_ids = GeneralUser.joins(:student_enrollments)
                                                  .where(student_enrollments: { class_number: class_no })
                                                  .pluck(:id)
            # 合併ID並篩選原始查詢
            @users = @users.where(id: (direct_users_ids + enrolled_class_users_ids).uniq)
          end

          # 修正：基於班級名稱篩選
          if params[:class_name].present?
            class_name = params[:class_name]
            # 分別獲取兩組用戶ID並合併
            direct_class_users_ids = GeneralUser.where(banbie: class_name).pluck(:id)
            enrolled_name_users_ids = GeneralUser.joins(:student_enrollments)
                                                 .where(student_enrollments: { class_name: })
                                                 .pluck(:id)
            # 合併ID並篩選原始查詢
            @users = @users.where(id: (direct_class_users_ids + enrolled_name_users_ids).uniq)
          end

          # 排序和格式化
          @users = @users.order(created_at: :desc).as_json(methods: [:locked_at])
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

        def create_aienglish_user
          ActiveRecord::Base.transaction do
            @user = GeneralUser.create!(general_users_params)

            # 創建energy
            @user.create_energy(value: 100)

            # 將 aienglish_features 存入 meta 欄位
            @user.aienglish_features_list = params[:aienglish_features] if params[:aienglish_features].present?

            # 將 role 存入 meta 欄位
            @user.aienglish_role = params[:role] if params[:role].present?

            raise ActiveRecord::RecordInvalid, @user unless @user.save

            # 構建 user_json 並返回
            user_json = @user.as_json
            user_json['role'] = @user.aienglish_role
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

        def update_aienglish_user
          @user = GeneralUser.find(params[:id])

          begin
            ActiveRecord::Base.transaction do
              # 更新 aienglish_features_list 到 meta 欄位
              @user.aienglish_features_list = params[:aienglish_features] if params[:aienglish_features].present?

              # 更新 role 到 meta 欄位
              @user.aienglish_role = params[:role] if params[:role].present?

              # 更新其他用戶屬性
              raise ActiveRecord::RecordInvalid, @user unless @user.update(general_users_params)

              # 構建 user_json，並返回角色信息
              user_json = @user.as_json
              user_json['role'] = @user.aienglish_role

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

          energy_insert_data = []
          role_insert_data = []
          aienglish_features_data = []
          roles_data = []
          errors = []
          inserted_users = []
          email = nil # 在方法的开头定义 email 变量

          begin
            CSV.foreach(file.path, headers: true) do |row|
              puts row['email']
              email = row['email']&.strip
              password = row['password']&.strip
              nickname = row['name']&.strip.to_s
              banbie = row['class_name']&.strip.to_s
              class_no = row['class_no']&.strip.to_s

              inserted_users << GeneralUser.create!(
                email:,
                password:,
                password_confirmation: password,
                nickname:,
                banbie:,
                class_no:
              )

              # 收集角色数据
              roles_data << { email:, role: row['role'] } if row['role'].present?

              # 收集 AI English features 数据
              if row['aienglish_features'].present?
                features = begin
                  JSON.parse(row['aienglish_features'].gsub(/[""]/, '"'))
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
              next unless feature_row.present?

              gu = GeneralUser.find(user_id)
              gu.aienglish_feature_list.add(feature_row[:features], parse: true)
              gu.save
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

        #用AI优化的批量创建，失败时会返回错误的email列表
        def batch_create_aienglish_user
          file = params[:file]
          return render json: { success: false, error: 'File not found' }, status: :bad_request if file.nil?

          users_data = []
          energy_insert_data = []
          errors = []
          inserted_users = []
          failed_emails = []
          all_emails = []
          
          # 第一步：收集所有数据并进行基础验证
          begin
            CSV.foreach(file.path, headers: true) do |row|
              email = row['email']&.strip&.downcase
              password = row['password']&.strip
              nickname = row['name']&.strip.to_s
              banbie = row['class_name']&.strip.to_s
              class_no = row['class_no']&.strip.to_s
              
              # 基础验证
              if email.blank? || password.blank?
                errors << { email: email || 'N/A', error: 'Email and password are required' }
                failed_emails << email
                next
              end
              
              # 收集所有邮箱用于批量查询
              all_emails << email
              
              # 处理 AI English features
              aienglish_features = []
              if row['aienglish_features'].present?
                aienglish_features = begin
                  JSON.parse(row['aienglish_features'].gsub(/[""""]/, '"'))
                rescue StandardError
                  []
                end
              end
              
              users_data << {
                email: email,
                password: password,
                nickname: nickname,
                banbie: banbie,
                class_no: class_no,
                aienglish_features: aienglish_features,
                aienglish_role: row['role']&.strip
              }
            end
          rescue StandardError => e
            return render json: { success: false, error: "CSV parsing error: #{e.message}" }, status: :bad_request
          end
          
          # 第二步：批量查询已存在的邮箱（性能优化关键点）
          existing_emails_set = Set.new
          if all_emails.any?
            existing_emails_set = Set.new(
              GeneralUser.where(email: all_emails.uniq).pluck(:email)
            )
          end
          
          # 第三步：过滤掉已存在的邮箱
          valid_users_data = []
          users_data.each do |user_data|
            if existing_emails_set.include?(user_data[:email])
              errors << { email: user_data[:email], error: 'Email already exists' }
              failed_emails << user_data[:email]
            else
              valid_users_data << user_data
            end
          end
          
          # 第四步：批量创建用户
          ActiveRecord::Base.transaction do
            valid_users_data.each do |user_data|
              begin
                user = GeneralUser.new(
                  email: user_data[:email],
                  password: user_data[:password],
                  password_confirmation: user_data[:password],
                  nickname: user_data[:nickname],
                  banbie: user_data[:banbie],
                  class_no: user_data[:class_no]
                )
                
                # 设置 meta 字段
                user.aienglish_features_list = user_data[:aienglish_features] if user_data[:aienglish_features].any?
                user.aienglish_role = user_data[:aienglish_role] if user_data[:aienglish_role].present?
                
                if user.save
                  inserted_users << user
                  # 准备 energy 数据
                  energy_insert_data << {
                    user_id: user.id,
                    user_type: 'GeneralUser',
                    value: 100,
                    created_at: Time.now,
                    updated_at: Time.now
                  }
                else
                  errors << { email: user_data[:email], error: user.errors.full_messages.join(', ') }
                  failed_emails << user_data[:email]
                end
              rescue StandardError => e
                errors << { email: user_data[:email], error: e.message }
                failed_emails << user_data[:email]
              end
            end
            
            # 批量插入 Energy 数据
            Energy.insert_all(energy_insert_data) if energy_insert_data.any?
          end
          
          # 返回结果
          total_count = users_data.length
          success_count = inserted_users.length
          failed_count = failed_emails.length
          
          render json: {
            success: errors.empty?,
            total_processed: total_count,
            successful_imports: success_count,
            failed_imports: failed_count,
            users: inserted_users.map { |u| { id: u.id, email: u.email, nickname: u.nickname } },
            failed_emails: failed_emails,
            errors: errors
          }, status: errors.empty? ? :created : :partial_content
        end

        #原来的批量创建
        def batch_create_aienglish_user_old
          file = params[:file]
          return render json: { success: false, error: 'File not found' }, status: :bad_request if file.nil?

          energy_insert_data = []
          errors = []
          inserted_users = []
          email = nil

          begin
            CSV.foreach(file.path, headers: true) do |row|
              email = row['email']&.strip&.downcase
              password = row['password']&.strip
              nickname = row['name']&.strip.to_s
              banbie = row['class_name']&.strip.to_s
              class_no = row['class_no']&.strip.to_s

              user = GeneralUser.create!(
                email:,
                password:,
                password_confirmation: password,
                nickname:,
                banbie:,
                class_no:
              )

              # 收集 AI English features 並保存到 meta 欄位
              if row['aienglish_features'].present?
                features = begin
                  JSON.parse(row['aienglish_features'].gsub(/[""]/, '"'))
                rescue StandardError
                  []
                end
                user.aienglish_features_list = features
              end

              # 收集角色並保存到 meta 欄位
              user.aienglish_role = row['role'] if row['role'].present?

              user.save!
              inserted_users << user

              # 批量創建 energy
              energy_insert_data << {
                user_id: user.id,
                user_type: 'GeneralUser',
                value: 100,
                created_at: Time.now,
                updated_at: Time.now
              }
            end

            # 批量插入 Energy 数据
            Energy.insert_all(energy_insert_data) if energy_insert_data.any?
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

        def batch_update_aienglish_user_old
          file = params[:file]
          return render json: { success: false, error: 'File not found' }, status: :bad_request if file.nil?

          errors = []
          updated_users = []
          email = nil

          begin
            CSV.foreach(file.path, headers: true) do |row|
              email = row['email']&.strip&.downcase
              next if email.blank?

              user = GeneralUser.find_by(email:)
              next unless user

              puts user.inspect

              # 更新 aienglish_features_list 到 meta 欄位
              if row['aienglish_features'].present?
                features = begin
                  JSON.parse(row['aienglish_features'].gsub(/[""]/, '"'))
                rescue JSON::ParserError
                  []
                end
                user.aienglish_features_list = features
              end

              # 更新 role 到 meta 欄位
              user.aienglish_role = row['role'] if row['role'].present?
              user.nickname = row['nickname'] if row['nickname'].present?

              user.banbie = row['class_name'] if row['class_name'].present?
              user.class_no = row['class_no'] if row['class_no'].present?

              user.password = row['password']&.strip if row['password'].present?
              user.password_confirmation = row['password']&.strip if row['password'].present?

              if user.save
                updated_users << user
              else
                errors << { email:, error: user.errors.full_messages.join(', ') }
              end
            end
          rescue StandardError => e
            errors << { email: email || 'N/A', error: e.message }
          end

          if errors.empty?
            render json: { success: true, users: updated_users }, status: :ok
          else
            render json: { success: false, errors: }, status: :unprocessable_entity
          end
        end

        def batch_update_aienglish_user
          file = params[:file]
          return render json: { success: false, error: 'File not found' }, status: :bad_request if file.nil?

          users_data = []
          errors = []
          updated_users = []
          failed_emails = []
          all_emails = []
          
          # 第一步：收集所有数据并进行基础验证
          begin
            CSV.foreach(file.path, headers: true) do |row|
              email = row['email']&.strip&.downcase
              
              # 基础验证
              if email.blank?
                errors << { email: 'N/A', error: 'Email is required' }
                failed_emails << email
                next
              end
              
              # 收集所有邮箱用于批量查询
              all_emails << email
              
              # 处理 AI English features
              aienglish_features = []
              if row['aienglish_features'].present?
                aienglish_features = begin
                  JSON.parse(row['aienglish_features'].gsub(/[""]/, '"'))
                rescue StandardError
                  []
                end
              end
              
              users_data << {
                email: email,
                nickname: row['nickname']&.strip,
                banbie: row['class_name']&.strip,
                class_no: row['class_no']&.strip,
                password: row['password']&.strip,
                aienglish_features: aienglish_features,
                aienglish_role: row['role']&.strip
              }
            end
          rescue StandardError => e
            return render json: { success: false, error: "CSV parsing error: #{e.message}" }, status: :bad_request
          end
          
          # 第二步：批量查询现有用户（性能优化关键点）
          existing_users_map = {}
          if all_emails.any?
            GeneralUser.where(email: all_emails.uniq).find_each do |user|
              existing_users_map[user.email] = user
            end
          end
          
          # 第三步：验证用户存在性并准备更新数据
          valid_users_data = []
          users_data.each do |user_data|
            user = existing_users_map[user_data[:email]]
            unless user
              errors << { email: user_data[:email], error: 'User not found' }
              failed_emails << user_data[:email]
              next
            end
            
            user_data[:user] = user
            valid_users_data << user_data
          end
          
          # 第四步：批量更新用户
          ActiveRecord::Base.transaction do
            valid_users_data.each do |user_data|
              begin
                user = user_data[:user]
                
                # 更新用户信息
                user.nickname = user_data[:nickname] if user_data[:nickname].present?
                user.banbie = user_data[:banbie] if user_data[:banbie].present?
                user.class_no = user_data[:class_no] if user_data[:class_no].present?
                
                if user_data[:password].present?
                  user.password = user_data[:password]
                  user.password_confirmation = user_data[:password]
                end
                
                # 设置 meta 字段
                user.aienglish_features_list = user_data[:aienglish_features] if user_data[:aienglish_features].any?
                user.aienglish_role = user_data[:aienglish_role] if user_data[:aienglish_role].present?
                
                if user.save
                  updated_users << user
                else
                  errors << { email: user_data[:email], error: user.errors.full_messages.join(', ') }
                  failed_emails << user_data[:email]
                end
              rescue StandardError => e
                errors << { email: user_data[:email], error: e.message }
                failed_emails << user_data[:email]
              end
            end
          end
          
          # 返回结果
          total_count = users_data.length
          success_count = updated_users.length
          failed_count = failed_emails.length
          
          render json: {
            success: errors.empty?,
            total_processed: total_count,
            successful_imports: success_count,
            failed_imports: failed_count,
            users: updated_users.map { |u| { id: u.id, email: u.email, nickname: u.nickname } },
            failed_emails: failed_emails,
            errors: errors
          }, status: errors.empty? ? :ok : :partial_content
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

        # 批量锁定用户 - 从CSV文件中读取邮箱并锁定对应用户
        def batch_lock_users
          file = params[:file]
          return render json: { success: false, error: 'File not found' }, status: :bad_request if file.nil?

          locked_users = []
          failed_emails = []
          errors = []
          processed_emails = Set.new

          begin
            CSV.foreach(file.path, headers: true) do |row|
              email = row['email']&.strip&.downcase
              
              # 跳过空邮箱或已处理的邮箱
              next if email.blank? || processed_emails.include?(email)
              processed_emails.add(email)
              
              # 查找用户
              user = GeneralUser.find_by(email: email)
              if user.nil?
                failed_emails << email
                errors << { email: email, error: 'User not found' }
                next
              end
              
              # 锁定用户
              if user.update(locked_at: Time.current)
                locked_users << { id: user.id, email: user.email }
              else
                failed_emails << email
                errors << { email: email, error: 'Failed to lock user' }
              end
            end

            result = {
              success: true,
              summary: {
                total_processed: processed_emails.size,
                locked_count: locked_users.size,
                failed_count: failed_emails.size
              },
              locked_users: locked_users,
              failed_emails: failed_emails,
              errors: errors
            }

            render json: result, status: :ok
          rescue CSV::MalformedCSVError => e
            render json: { success: false, error: "CSV format error: #{e.message}" }, status: :bad_request
          rescue StandardError => e
            render json: { success: false, error: e.message }, status: :internal_server_error
          end
        end

        # 批量解锁用户 - 从CSV文件中读取邮箱并解锁对应用户
        def batch_unlock_users
          file = params[:file]
          return render json: { success: false, error: 'File not found' }, status: :bad_request if file.nil?

          unlocked_users = []
          failed_emails = []
          errors = []
          processed_emails = Set.new

          begin
            CSV.foreach(file.path, headers: true) do |row|
              email = row['email']&.strip&.downcase
              
              # 跳过空邮箱或已处理的邮箱
              next if email.blank? || processed_emails.include?(email)
              processed_emails.add(email)
              
              # 查找用户
              user = GeneralUser.find_by(email: email)
              if user.nil?
                failed_emails << email
                errors << { email: email, error: 'User not found' }
                next
              end
              
              # 解锁用户
              if user.update(locked_at: nil, failed_attempts: 0, unlock_token: nil)
                unlocked_users << { id: user.id, email: user.email }
              else
                failed_emails << email
                errors << { email: email, error: 'Failed to unlock user' }
              end
            end

            result = {
              success: true,
              summary: {
                total_processed: processed_emails.size,
                unlocked_count: unlocked_users.size,
                failed_count: failed_emails.size
              },
              unlocked_users: unlocked_users,
              failed_emails: failed_emails,
              errors: errors
            }

            render json: result, status: :ok
          rescue CSV::MalformedCSVError => e
            render json: { success: false, error: "CSV format error: #{e.message}" }, status: :bad_request
          rescue StandardError => e
            render json: { success: false, error: e.message }, status: :internal_server_error
          end
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

        def check_emails_existence
          file = params[:file]
          return render json: { success: false, error: 'File not found' }, status: :bad_request if file.nil?

          existing_emails = []
          non_existing_emails = []
          invalid_emails = []
          processed_emails = Set.new # 用于去重

          begin
            CSV.foreach(file.path, headers: true) do |row|
              email = row['email']&.strip&.downcase || row['Email']&.strip&.downcase
              
              # 跳过空邮箱或已处理的邮箱
              next if email.blank? || processed_emails.include?(email)
              
              processed_emails.add(email)
              
              # 简单的邮箱格式验证
              if email.match?(/\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i)
                if GeneralUser.exists?(email: email)
                  existing_emails << email
                else
                  non_existing_emails << email
                end
              else
                invalid_emails << email
              end
            end

            result = {
              success: true,
              summary: {
                total_processed: processed_emails.size,
                existing_count: existing_emails.size,
                non_existing_count: non_existing_emails.size,
                invalid_count: invalid_emails.size
              },
              existing_emails: existing_emails,
              non_existing_emails: non_existing_emails,
              invalid_emails: invalid_emails
            }

            render json: result, status: :ok
          rescue CSV::MalformedCSVError => e
            render json: { success: false, error: "CSV format error: #{e.message}" }, status: :bad_request
          rescue StandardError => e
            render json: { success: false, error: e.message }, status: :internal_server_error
          end
        end

        # AI English 用户统计API - 统计角色数量和功能特性使用情况
        def aienglish_statistics
          begin
            # 获取所有有meta数据的用户（性能优化：只查询需要的字段）
            users = GeneralUser.where.not(meta: nil).select(:id, :meta, :created_at)
            
            # 初始化统计数据
            role_stats = {
              'teacher' => 0,
              'student' => 0,
              'unknown' => 0
            }
            
            # 定义功能特性列表
            features_list = [
              'essay',
              'comprehension', 
              'speaking_essay',
              'speaking_conversation',
              'sentence_builder',
              'speaking_pronunciation',
              'talk_lab_speaking'
            ]
            
            # 初始化功能特性统计
            feature_stats = {
              'teacher' => {},
              'student' => {},
              'total' => {}
            }
            
            # 为每个角色和总计初始化功能特性计数
            features_list.each do |feature|
              feature_stats['teacher'][feature] = 0
              feature_stats['student'][feature] = 0
              feature_stats['total'][feature] = 0
            end
            
            # 遍历用户进行统计
            users.find_each do |user|
              # 安全地获取用户角色
              role = user.meta&.dig('aienglish_role') || 'unknown'
              role = 'unknown' unless role_stats.key?(role)
              
              # 统计角色数量
              role_stats[role] += 1
              
              # 获取用户的功能特性列表
              user_features = user.meta&.dig('aienglish_features_list') || []
              
              # 如果功能特性是字符串，尝试解析为数组
              if user_features.is_a?(String)
                begin
                  user_features = JSON.parse(user_features)
                rescue JSON::ParserError
                  user_features = []
                end
              end
              
              # 确保是数组格式
              user_features = Array(user_features)
              
              # 统计每个功能特性的使用情况
              features_list.each do |feature|
                if user_features.include?(feature)
                  # 为对应角色增加计数
                  if role != 'unknown'
                    feature_stats[role][feature] += 1
                  end
                  # 总计增加计数
                  feature_stats['total'][feature] += 1
                end
              end
            end
            
            # 计算总用户数
            total_users = role_stats.values.sum
            
            # 构建响应数据
            result = {
              success: true,
              statistics: {
                # 角色统计
                role_distribution: {
                  teacher_count: role_stats['teacher'],
                  student_count: role_stats['student'],
                  unknown_count: role_stats['unknown'],
                  total_count: total_users
                },
                
                # 功能特性使用统计
                feature_usage: {
                  by_role: {
                    teacher: feature_stats['teacher'],
                    student: feature_stats['student']
                  },
                  total: feature_stats['total']
                },
                
                # 计算使用率百分比
                usage_percentage: {
                  teacher: {},
                  student: {},
                  total: {}
                }
              },
              
              # 元数据
              metadata: {
                features_list: features_list,
                generated_at: Time.current.iso8601,
                total_analyzed_users: total_users
              }
            }
            
            # 计算使用率百分比（避免除零错误）
            if role_stats['teacher'] > 0
              features_list.each do |feature|
                percentage = (feature_stats['teacher'][feature].to_f / role_stats['teacher'] * 100).round(2)
                result[:statistics][:usage_percentage][:teacher][feature] = percentage
              end
            end
            
            if role_stats['student'] > 0
              features_list.each do |feature|
                percentage = (feature_stats['student'][feature].to_f / role_stats['student'] * 100).round(2)
                result[:statistics][:usage_percentage][:student][feature] = percentage
              end
            end
            
            if total_users > 0
              features_list.each do |feature|
                percentage = (feature_stats['total'][feature].to_f / total_users * 100).round(2)
                result[:statistics][:usage_percentage][:total][feature] = percentage
              end
            end
            
            render json: result, status: :ok
            
          rescue StandardError => e
            render json: { 
              success: false, 
              error: e.message,
              details: "Error occurred while generating AI English statistics"
            }, status: :internal_server_error
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
