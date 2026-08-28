# frozen_string_literal: true

module Api
  module V1
    class GeneralUsersController < ApiController
      before_action :authenticate_general_user!,
                    only: %i[
                      show show_current_user show_purchase_history update delete
                      show_aienglish_profile show_aienglish_memberships
                    ]

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

        # AIEnglish 轻量资料：基本信息 + 当前学校（header/logo），不含 teaching_assignments
      def show_aienglish_profile
        @user = current_general_user

        unless @user.aienglish_user?
          return render json: { success: false, error: 'User is not an AIEnglish user' }, status: :bad_request
        end

        aienglish_data = aienglish_basic_user_hash(@user)
        aienglish_data[:school] = aienglish_current_school_json(@user)

        render json: { success: true, user: aienglish_data }, status: :ok
      rescue ArgumentError => e
        Rails.logger.error("[GeneralUsersController#show_aienglish_profile] ArgumentError: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
        render json: { success: false, error: "Invalid arguments: #{e.message}" }, status: :internal_server_error
      rescue StandardError => e
        Rails.logger.error("[GeneralUsersController#show_aienglish_profile] Error: #{e.class.name}: #{e.message}\n#{e.backtrace.first(10).join("\n")}")
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      # AIEnglish 组织关系：teaching_assignments / enrollments（学年筛选、settings 等）
      def show_aienglish_memberships
        @user = current_general_user

        unless @user.aienglish_user?
          return render json: { success: false, error: 'User is not an AIEnglish user' }, status: :bad_request
        end

        payload = { role: @user.aienglish_role }

        if @user.aienglish_role == 'teacher'
          payload[:teaching_assignments] = aienglish_teaching_assignments_json(@user)
        else
          payload[:enrollments] = aienglish_enrollments_json(@user)
          payload[:teachers] = aienglish_student_teachers_json(@user)
        end

        render json: { success: true, memberships: payload }, status: :ok
      rescue StandardError => e
        Rails.logger.error("[GeneralUsersController#show_aienglish_memberships] Error: #{e.class.name}: #{e.message}\n#{e.backtrace.first(10).join("\n")}")
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      private

      def aienglish_basic_user_hash(user)
        user_meta = user.meta
        user_meta = {} if user_meta.nil?
        user_meta = user_meta.to_h if user_meta.respond_to?(:to_h) && !user_meta.is_a?(Hash)
        filtered_meta = user_meta.is_a?(Hash) ? user_meta.except('konnecai_tokens') : {}

        {
          id: user.id,
          email: user.email,
          nickname: user.nickname,
          phone: user.phone,
          date_of_birth: user.date_of_birth,
          sex: user.sex,
          timezone: user.timezone,
          whats_app_number: user.whats_app_number,
          banbie: user.banbie,
          class_no: user.class_no,
          created_at: user.created_at,
          updated_at: user.updated_at,
          meta: filtered_meta,
          recovery_email: user.recovery_email,
          is_recovery_email_confirmed: user.recovery_email_confirmed?,
          recovery_email_confirmed_at: user.recovery_email_confirmed_at
        }
      end

      def aienglish_current_school_json(user)
        scope =
          if user.aienglish_role == 'teacher'
            user.teacher_assignments
          else
            user.student_enrollments
          end

        membership = scope
                     .includes(school_academic_year: { school: { logo_attachment: :blob } })
                     .joins(:school_academic_year)
                     .where(school_academic_years: { status: SchoolAcademicYear.statuses[:active] })
                     .order(created_at: :desc)
                     .first

        membership ||= scope
                       .includes(school_academic_year: { school: { logo_attachment: :blob } })
                       .order(created_at: :desc)
                       .first

        membership&.school_academic_year&.school&.as_aienglish_ui_json
      end

      def aienglish_teaching_assignments_json(user)
        assignments = user.teacher_assignments
                          .includes(school_academic_year: { school: { logo_attachment: :blob } })
                          .order(created_at: :desc)

        school_cache = {}
        assignments.map do |assignment|
          school_academic_year = assignment.school_academic_year
          school = school_academic_year&.school
          school_data =
            if school
              school_cache[school.id] ||= school.as_aienglish_ui_json
            end

          {
            id: assignment.id,
            school: school_data,
            academic_year: school_academic_year && {
              id: school_academic_year.id,
              name: school_academic_year.name,
              status: school_academic_year.status
            },
            department: assignment.department,
            position: assignment.position,
            created_at: assignment.created_at
          }
        end
      end

      def aienglish_enrollments_json(user)
        enrollments = user.student_enrollments
                          .includes(school_academic_year: { school: { logo_attachment: :blob } })
                          .order(created_at: :desc)

        school_cache = {}
        enrollments.filter_map do |enrollment|
          school_academic_year = enrollment.school_academic_year
          school = school_academic_year&.school
          next unless school_academic_year && school

          school_data = school_cache[school.id] ||= school.as_aienglish_ui_json

          {
            id: enrollment.id,
            school: school_data,
            academic_year: {
              id: school_academic_year.id,
              name: school_academic_year.name,
              status: school_academic_year.status
            },
            class_name: enrollment.class_name,
            class_number: enrollment.class_number,
            created_at: enrollment.created_at
          }
        end
      end

      def aienglish_student_teachers_json(user)
        teacher_ids = KgLinker.where(map_to_id: user.id, relation: 'has_student')
                              .distinct
                              .pluck(:map_from_id)
        return [] if teacher_ids.blank?

        GeneralUser.where(id: teacher_ids)
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
      end

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
