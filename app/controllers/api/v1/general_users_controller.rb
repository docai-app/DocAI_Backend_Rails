# frozen_string_literal: true

module Api
  module V1
    class GeneralUsersController < ApiController
      before_action :authenticate_general_user!,
                    only: %i[show show_current_user show_purchase_history update delete show_aienglish_profile]

      def show
        @user = current_general_user
        render json: { success: true, user: @user.as_json(except: [:konnecai_tokens]) }, status: :ok
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      def show_current_user
        @user = current_general_user

        # 獲取基本用戶數據，排除 konnecai_tokens
        user_data = @user.as_json(except: [:konnecai_tokens])

        # 檢查是否需要包含 AIEnglish 相關資訊（可通過請求參數或請求來源判斷）
        include_aienglish = params[:include_aienglish].present? || request.referer&.include?('aienglish')

        if include_aienglish && @user.aienglish_user?
          # 添加 AIEnglish 相關資訊
          user_data['aienglish'] = {
            role: @user.aienglish_role,
            features: @user.aienglish_features_list,
            is_aienglish_user: true
          }

          # 獲取學校資訊（如果有的話）
          if @user.school.present?
            user_data['aienglish']['school'] = @user.school.as_json(only: %i[id name code]).merge(
              logo_url: @user.school.logo_url,
              logo_thumbnail_url: @user.school.logo_thumbnail_url,
              logo_small_url: @user.school.logo_small_url,
              logo_large_url: @user.school.logo_large_url,
              logo_square_url: @user.school.logo_square_url
            )
          end

          # 根據角色獲取不同的資訊
          if @user.aienglish_role == 'teacher'
            # 獲取教師資訊
            current_assignment = @user.current_teaching_assignment
            if current_assignment
              user_data['aienglish']['teaching'] = {
                school: current_assignment.school_academic_year.school.as_json(only: %i[id name code]).merge(
                  logo_url: current_assignment.school_academic_year.school.logo_url,
                  logo_thumbnail_url: current_assignment.school_academic_year.school.logo_thumbnail_url,
                  logo_small_url: current_assignment.school_academic_year.school.logo_small_url,
                  logo_large_url: current_assignment.school_academic_year.school.logo_large_url,
                  logo_square_url: current_assignment.school_academic_year.school.logo_square_url
                ),
                academic_year: current_assignment.school_academic_year.as_json(only: %i[id year name status]),
                department: current_assignment.department,
                position: current_assignment.position
              }

              # 獲取所有教學記錄
              user_data['aienglish']['teaching_history'] = @user.teacher_assignments.includes(school_academic_year: :school).map do |assignment|
                {
                  id: assignment.id,
                  school: assignment.school_academic_year.school.as_json(only: %i[id name code]).merge(
                    logo_url: assignment.school_academic_year.school.logo_url,
                    logo_thumbnail_url: assignment.school_academic_year.school.logo_thumbnail_url,
                    logo_small_url: assignment.school_academic_year.school.logo_small_url,
                    logo_large_url: assignment.school_academic_year.school.logo_large_url,
                    logo_square_url: assignment.school_academic_year.school.logo_square_url
                  ),
                  academic_year: assignment.school_academic_year.as_json(only: %i[id year name status]),
                  department: assignment.department,
                  position: assignment.position,
                  created_at: assignment.created_at
                }
              end
            end

            # 獲取教師的學生
            student_ids = KgLinker.where(map_from_id: @user.id, relation: 'has_student').pluck(:map_to_id).uniq
            user_data['aienglish']['students_count'] = student_ids.count if student_ids.present?
          else
            # 獲取學生資訊
            current_enroll = @user.current_enrollment
            if current_enroll
              user_data['aienglish']['learning'] = {
                school: current_enroll.school_academic_year.school.as_json(only: %i[id name code]).merge(
                  logo_url: current_enroll.school_academic_year.school.logo_url,
                  logo_thumbnail_url: current_enroll.school_academic_year.school.logo_thumbnail_url,
                  logo_small_url: current_enroll.school_academic_year.school.logo_small_url,
                  logo_large_url: current_enroll.school_academic_year.school.logo_large_url,
                  logo_square_url: current_enroll.school_academic_year.school.logo_square_url
                ),
                academic_year: current_enroll.school_academic_year.as_json(only: %i[id year name status]),
                class_name: current_enroll.class_name,
                class_number: current_enroll.class_number
              }

              # 獲取所有學籍記錄
              user_data['aienglish']['enrollment_history'] = @user.student_enrollments.includes(school_academic_year: :school).map do |enrollment|
                {
                  id: enrollment.id,
                  school: enrollment.school_academic_year.school.as_json(only: %i[id name code]).merge(
                    logo_url: enrollment.school_academic_year.school.logo_url,
                    logo_thumbnail_url: enrollment.school_academic_year.school.logo_thumbnail_url,
                    logo_small_url: enrollment.school_academic_year.school.logo_small_url,
                    logo_large_url: enrollment.school_academic_year.school.logo_large_url,
                    logo_square_url: enrollment.school_academic_year.school.logo_square_url
                  ),
                  academic_year: enrollment.school_academic_year.as_json(only: %i[id year name status]),
                  class_name: enrollment.class_name,
                  class_number: enrollment.class_number,
                  created_at: enrollment.created_at
                }
              end

              # 獲取學生的教師
              teachers = @user.find_teachers_via_students
              user_data['aienglish']['teachers'] = teachers if teachers.present?
            end
          end

          # 獲取用戶的學習記錄統計
          if @user.essay_assignments.present?
            user_data['aienglish']['learning_stats'] = {
              essay_assignments_count: @user.essay_assignments.count,
              essay_gradings_count: @user.essay_gradings.count
            }
          end
        end

        render json: { success: true, user: user_data }, status: :ok
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      def show_purchase_history
        @user = current_general_user
        @purchases = @user.purchased_items
        render json: { success: true, purchases: @purchases }, status: :ok
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      def show_marketplace_items
        @user = current_general_user
        search_query = @user.user_marketplace_items.ransack(custom_name_cont: params[:custom_name])
        @user_marketplace_items = search_query.result(distinct: true).page(params[:page])
        render json: { success: true, user_marketplace_items: @user_marketplace_items, meta: pagination_meta(@user_marketplace_items) },
               status: :ok
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      def show_marketplace_item
        @user = current_general_user
        @user_marketplace_item = @user.user_marketplace_items.find_by(id: params[:id])
        Apartment::Tenant.switch!(@user_marketplace_item.marketplace_item.entity_name)
        @chatbot_detail = Chatbot.find_by(id: @user_marketplace_item.marketplace_item.chatbot_id)
        render json: { success: true, user_marketplace_item: @user_marketplace_item, chatbot_detail: @chatbot_detail },
               status: :ok
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      def show_files
        type = params[:type] || 'image'
        @user = current_general_user
        if type == 'image'
          @files = @user.general_user_files.where(file_type: %w[png jpg]).order(created_at: :desc).page(params[:page])
          render json: { success: true, files: @files, meta: pagination_meta(@files) }, status: :ok
        elsif type == 'document'
          @files = @user.general_user_files.where(file_type: %w[pdf]).order(created_at: :desc).page(params[:page])
          render json: { success: true, files: @files, meta: pagination_meta(@files) }, status: :ok
        end
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      def create
        @user = GeneralUser.new(user_params)
        if @user.save
          @user.create_energy(value: 100)
          render json: { success: true, user: @user }, status: :ok
        else
          render json: { success: false, errors: @user.errors }, status: :ok
        end
      end

      def update
        @user = current_general_user
        if @user.update(user_params)
          render json: { success: true, user: @user }, status: :ok
        else
          render json: { success: false, errors: @user.errors }, status: :ok
        end
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      # Write a method to update user his own profile
      def update_profile
        @user = current_general_user
        if @user.update(general_user_profile_params)
          render json: { success: true, user: @user }, status: :ok
        else
          render json: { success: false, errors: @user.errors }, status: :ok
        end
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      # Write a method to update user his own password
      def update_password
        @user = current_general_user
        if @user.update_with_password({ current_password: params[:current_password], password: params[:password],
                                        password_confirmation: params[:password_confirmation] })
          render json: { success: true, user: @user }, status: :ok
        else
          render json: { success: false, errors: @user.errors }, status: :ok
        end
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      def destroy_file
        @user = current_general_user
        @user.general_user_files.find_by(id: params[:id]).destroy
        render json: { success: true }, status: :ok
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

        # AIEnglish 專用用戶資料方法
      def show_aienglish_profile
        @user = current_general_user

        # 檢查是否為 AIEnglish 用戶
        unless @user.aienglish_user?
          return render json: { success: false, error: 'User is not an AIEnglish user' }, status: :bad_request
        end

        # 優化：手動構建用戶資料，只選擇需要的字段，避免 as_json 的開銷
        # 安全處理 meta 字段，確保不為 nil 且是 Hash 類型
        user_meta = @user.meta
        user_meta = {} if user_meta.nil?
        user_meta = user_meta.to_h if user_meta.respond_to?(:to_h) && !user_meta.is_a?(Hash)
        filtered_meta = user_meta.is_a?(Hash) ? user_meta.except('konnecai_tokens') : {}

        aienglish_data = {
          id: @user.id,
          email: @user.email,
          nickname: @user.nickname,
          phone: @user.phone,
          date_of_birth: @user.date_of_birth,
          sex: @user.sex,
          timezone: @user.timezone,
          whats_app_number: @user.whats_app_number,
          banbie: @user.banbie,
          class_no: @user.class_no,
          created_at: @user.created_at,
          updated_at: @user.updated_at, 
          meta: filtered_meta,
          recovery_email: @user.recovery_email,
          is_recovery_email_confirmed: @user.recovery_email_confirmed?,
          recovery_email_confirmed_at: @user.recovery_email_confirmed_at
        }

        # 根據角色獲取不同的資訊
        if @user.aienglish_role == 'teacher'
          # 獲取教師資訊
          # 優化：使用 includes 預加載關聯，避免 N+1 查詢
          # 注意：不使用 select，避免在多租戶環境下觸發 schema 查詢（pg_attribute）
          assignments = @user.teacher_assignments
                             .includes(school_academic_year: { school: { logo_attachment: :blob } })
                             .order(created_at: :desc)

          # 優化：批量處理，減少重複的 logo URL 生成
          school_logo_cache = {}
          aienglish_data[:teaching_assignments] = assignments.map do |assignment|
            school_academic_year = assignment.school_academic_year
            school = school_academic_year&.school

            # 緩存 logo URLs，避免重複生成
            school_data = if school
                            cache_key = school.id
                            unless school_logo_cache[cache_key]
                              school_logo_cache[cache_key] = {
                                id: school.id,
                                name: school.name,
                                code: school.code
                              }.merge(school.all_logo_urls)
                            end
                            school_logo_cache[cache_key]
                          else
                            nil
                          end

            academic_year_data = if school_academic_year
                                   {
                                     id: school_academic_year.id,
                                     name: school_academic_year.name,
                                     status: school_academic_year.status
                                   }
                                 else
                                   nil
                                 end

            {
              id: assignment.id,
              school: school_data,
              academic_year: academic_year_data,
              department: assignment.department,
              position: assignment.position,
              created_at: assignment.created_at
            }
          end

          # 優化：直接使用 count，避免先 pluck 再 count
        #   students_count = KgLinker.where(map_from_id: @user.id, relation: 'has_student')
                                #    .select(:map_to_id)
                                #    .distinct
                                #    .count
        #   aienglish_data[:students_count] = students_count if students_count > 0
        else
          # 獲取學生資訊
          # 優化：使用 includes 預加載關聯，避免 N+1 查詢
          # 注意：不使用 select，避免在多租戶環境下觸發 schema 查詢（pg_attribute）
          enrollments = @user.student_enrollments
                             .includes(school_academic_year: { school: { logo_attachment: :blob } })
                             .order(created_at: :desc)

          if enrollments.any?
            school_logo_cache = {}
            aienglish_data[:enrollments] = enrollments.filter_map do |enrollment|
              school_academic_year = enrollment.school_academic_year
              school = school_academic_year&.school
              next unless school_academic_year && school

              school_data = school_logo_cache[school.id] ||= {
                id: school.id,
                name: school.name,
                code: school.code
              }.merge(school.all_logo_urls)

              academic_year_data = {
                id: school_academic_year.id,
                name: school_academic_year.name,
                status: school_academic_year.status
              }

              {
                id: enrollment.id,
                school: school_data,
                academic_year: academic_year_data,
                class_name: enrollment.class_name,
                class_number: enrollment.class_number,
                created_at: enrollment.created_at
              }
            end
          else
            aienglish_data[:enrollments] = []
          end

          # 優化：只在需要時查詢教師，使用 pluck 直接獲取值，避免 ActiveRecord 對象和 schema 查詢
          teacher_ids = KgLinker.where(map_to_id: @user.id, relation: 'has_student')
                                .distinct
                                .pluck(:map_from_id)
          if teacher_ids.present?
            # 使用 pluck 直接獲取值，避免 ActiveRecord 對象創建和 schema 查詢
            aienglish_data[:teachers] = GeneralUser.where(id: teacher_ids)
                                                    .order(created_at: :desc)
                                                    .pluck(:id, :email, :nickname, :phone, :created_at, :updated_at)
                                                    .map do |id, email, nickname, phone, created_at, updated_at|
              {
                id: id,
                email: email,
                nickname: nickname,
                phone: phone,
                created_at: created_at,
                updated_at: updated_at
              }
            end
          else
            aienglish_data[:teachers] = []
          end
        end

        render json: { success: true, user: aienglish_data }, status: :ok
      rescue ArgumentError => e
        # 捕获参数错误，可能是 fallback 参数缺失
        Rails.logger.error("[GeneralUsersController#show_aienglish_profile] ArgumentError: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
        render json: { success: false, error: "Invalid arguments: #{e.message}" }, status: :internal_server_error
      rescue StandardError => e
        # 记录完整的错误信息以便调试
        Rails.logger.error("[GeneralUsersController#show_aienglish_profile] Error: #{e.class.name}: #{e.message}\n#{e.backtrace.first(10).join("\n")}")
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      private

      def user_params
        params.permit(:email, :password, :nickname, :phone, :date_of_birth, :sex)
      end

      def general_user_profile_params
        params.permit(:nickname, :phone, :date_of_birth, :sex)
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
