# frozen_string_literal: true

module Api
  module Admin
    module V1
      # 學校管理控制器
      # 提供學校創建、列表、分配學生/教師等功能的 API 端點
      class SchoolsController < AdminApiController
        before_action :set_school, only: %i[show update destroy assign_students
                                            assign_teachers student_stats teacher_stats
                                            academic_year_students class_students
                                            academic_year_teachers department_teachers
                                            academic_years]

        # GET /admin/v1/schools
        # 獲取所有學校的列表
        # @return [JSON] 所有學校的詳細信息
        def index
          @schools = School.all.order(created_at: :desc)

          # 分頁處理
          @schools = @schools.page(params[:page] || 1).per(params[:per_page] || 20)

          render json: {
            status: 'success',
            data: @schools.map { |school| school_serializer(school) },
            meta: pagination_meta(@schools)
          }
        end

        # GET /admin/v1/schools/:code
        # 獲取特定學校的詳細信息
        # @param code [String] 學校代碼
        # @return [JSON] 學校的詳細信息
        def show
          render json: {
            status: 'success',
            data: school_serializer(@school)
          }
        end

        # GET /admin/v1/schools/:code/academic_years
        # 獲取特定學校的所有學年列表
        # @param code [String] 學校代碼
        # @param status [String] 可選，按狀態過濾學年
        # @param sort_by [String] 可選，排序字段，默認為 'start_date'
        # @param sort_direction [String] 可選，排序方向，'asc' 或 'desc'，默認為 'desc'
        # @return [JSON] 學年列表及相關統計信息
        def academic_years
          # 獲取學年列表
          academic_years = @school.school_academic_years

          # 狀態過濾
          academic_years = academic_years.where(status: params[:status]) if params[:status].present?

          # 排序
          sort_by = params[:sort_by].present? ? params[:sort_by].to_sym : :start_date
          sort_direction = params[:sort_direction] == 'asc' ? :asc : :desc
          academic_years = academic_years.order(sort_by => sort_direction)

          # 統計數據
          active_count = @school.school_academic_years.where(status: :active).count
          archived_count = @school.school_academic_years.where(status: :archived).count
          preparing_count = @school.school_academic_years.where(status: :preparing).count

          render json: {
            status: 'success',
            code: 200,
            data: academic_years.map { |academic_year| academic_year_serializer(academic_year) },
            meta: {
              total_count: academic_years.count,
              active_count:,
              archived_count:,
              preparing_count:
            }
          }
        end

        # POST /admin/v1/schools
        # 創建新學校
        # @param school [Hash] 學校信息
        # @return [JSON] 新創建的學校信息
        def create
          service = Schools::SchoolCreator.new(school_params)

          if service.execute
            render json: {
              status: 'success',
              message: "成功創建學校: #{service.school.name}",
              data: school_serializer(service.school)
            }, status: :created
          else
            render json: {
              status: 'error',
              errors: service.errors.full_messages
            }, status: :unprocessable_entity
          end
        end

        # PUT/PATCH /admin/v1/schools/:code
        # 更新學校信息
        # @param code [String] 學校代碼
        # @param school [Hash] 更新的學校信息
        # @return [JSON] 更新後的學校信息
        def update
          service = Schools::SchoolUpdater.new(@school, school_params)

          if service.execute
            render json: {
              status: 'success',
              message: "成功更新學校: #{@school.name}",
              data: school_serializer(@school)
            }
          else
            render json: {
              status: 'error',
              errors: service.errors.full_messages
            }, status: :unprocessable_entity
          end
        end

        # DELETE /admin/v1/schools/:code
        # 刪除學校（軟刪除或標記為非活躍）
        # @param code [String] 學校代碼
        # @return [JSON] 操作結果
        def destroy
          if @school.update(status: :inactive)
            render json: {
              status: 'success',
              message: "學校 #{@school.name} 已設置為非活躍狀態"
            }
          else
            render json: {
              status: 'error',
              errors: @school.errors.full_messages
            }, status: :unprocessable_entity
          end
        end

        # POST /admin/v1/schools/:code/assign_students
        # 為學校分配學生
        # @param code [String] 學校代碼
        # @param academic_year_name [String] 學年名稱
        # @param email_patterns [String] 郵箱模式，用分號分隔多個模式
        # @return [JSON] 分配結果
        def assign_students
          service = Schools::StudentAssigner.new(
            school: @school,
            academic_year_name: params[:academic_year_name],
            email_patterns: params[:email_patterns]
          )

          if service.execute
            render json: {
              status: 'success',
              message: '學生分配成功',
              data: {
                total_processed: service.total_processed,
                assigned_count: service.assigned_count,
                skipped_count: service.skipped_count,
                validation_errors: service.validation_errors
              }
            }
          else
            render json: {
              status: 'error',
              errors: service.errors.full_messages
            }, status: :unprocessable_entity
          end
        end

        # POST /admin/v1/schools/:code/assign_teachers
        # 為學校分配教師
        # @param code [String] 學校代碼
        # @param academic_year_name [String] 學年名稱
        # @param email_patterns [String] 郵箱模式，用分號分隔多個模式
        # @param department [String] 部門名稱
        # @param position [String] 職位名稱
        # @return [JSON] 分配結果
        def assign_teachers
          service = Schools::TeacherAssigner.new(
            school: @school,
            academic_year_name: params[:academic_year_name],
            email_patterns: params[:email_patterns],
            department: params[:department],
            position: params[:position]
          )

          if service.execute
            render json: {
              status: 'success',
              message: '教師分配成功',
              data: {
                total_processed: service.total_processed,
                assigned_count: service.assigned_count,
                skipped_count: service.skipped_count
              }
            }
          else
            render json: {
              status: 'error',
              errors: service.errors.full_messages
            }, status: :unprocessable_entity
          end
        end

        # GET /admin/v1/schools/:code/student_stats
        # 獲取學校學生統計信息
        # @param code [String] 學校代碼
        # @return [JSON] 學生統計信息
        def student_stats
          service = Schools::StudentStatsGenerator.new(@school)

          render json: {
            status: 'success',
            data: service.generate
          }
        end

        # GET /admin/v1/schools/:code/teacher_stats
        # 獲取學校教師統計信息
        # @param code [String] 學校代碼
        # @return [JSON] 教師統計信息
        def teacher_stats
          service = Schools::TeacherStatsGenerator.new(@school)

          render json: {
            status: 'success',
            data: service.generate
          }
        end

        # POST /admin/v1/schools/import_from_csv
        # 從CSV文件批量導入學校
        # @param file [File] CSV文件
        # @return [JSON] 導入結果
        def import_from_csv
          if params[:file].blank?
            return render json: {
              status: 'error',
              errors: ['請上傳CSV文件']
            }, status: :bad_request
          end

          service = Schools::CsvImporter.new(params[:file])

          if service.execute
            render json: {
              status: 'success',
              message: '學校導入成功',
              data: {
                imported_count: service.imported_count,
                failed_count: service.failed_count,
                errors: service.import_errors
              }
            }
          else
            render json: {
              status: 'error',
              errors: service.errors.full_messages
            }, status: :unprocessable_entity
          end
        end

        # POST /admin/v1/schools/bulk_assign_students
        # 批量分配學生到多個學校
        # @param assignments [Array<Hash>] 分配信息數組
        # @return [JSON] 分配結果
        def bulk_assign_students
          service = Schools::BulkStudentAssigner.new(bulk_students_params)

          if service.execute
            render json: {
              status: 'success',
              message: '批量學生分配成功',
              data: {
                total_processed: service.total_processed,
                success_count: service.success_count,
                failed_count: service.failed_count,
                errors: service.assignment_errors
              }
            }
          else
            render json: {
              status: 'error',
              errors: service.errors.full_messages
            }, status: :unprocessable_entity
          end
        end

        # POST /admin/v1/schools/bulk_assign_teachers
        # 批量分配教師到多個學校
        # @param assignments [Array<Hash>] 分配信息數組
        # @return [JSON] 分配結果
        def bulk_assign_teachers
          service = Schools::BulkTeacherAssigner.new(bulk_teachers_params)

          if service.execute
            render json: {
              status: 'success',
              message: '批量教師分配成功',
              data: {
                total_processed: service.total_processed,
                success_count: service.success_count,
                failed_count: service.failed_count,
                errors: service.assignment_errors
              }
            }
          else
            render json: {
              status: 'error',
              errors: service.errors.full_messages
            }, status: :unprocessable_entity
          end
        end

        # 通過 email 分配學生到學校
        def assign_student_by_email
          @school = School.find_by(code: params[:code])
          return render json: { success: false, error: '找不到指定的學校' }, status: :not_found unless @school

          @academic_year = @school.school_academic_years.find_by(name: params[:academic_year_name])
          return render json: { success: false, error: '找不到指定的學年' }, status: :not_found unless @academic_year

          @user = GeneralUser.find_by(email: params[:email])
          return render json: { success: false, error: '找不到指定的用戶' }, status: :not_found unless @user

          # 檢查用戶是否為 AI English 學生
          unless @user.aienglish_user? && @user.meta['aienglish_role'] != 'teacher'
            return render json: { success: false, error: '該用戶不是 AI English 學生' }, status: :unprocessable_entity
          end

          # 創建或更新學生註冊記錄
          enrollment = StudentEnrollment.find_or_initialize_by(
            general_user: @user,
            school_academic_year: @academic_year
          )

          if enrollment.new_record?
            enrollment.class_name = @user.banbie.presence || '未分配'
            enrollment.class_number = @user.class_no.presence || '未分配'
            enrollment.status = :active
          end

          # 嘗試保存記錄，如果驗證失敗會被rescue捕獲
          if enrollment.save
            # 更新該用戶的所有未完成的 EssayGrading 記錄
            update_essay_gradings(@user, @school, @academic_year, enrollment)
            render json: { success: true, message: '學生分配成功', enrollment: }, status: :ok
          else
            # 直接返回模型驗證錯誤
            render json: { success: false, error: enrollment.errors.full_messages.join(', ') },
                   status: :unprocessable_entity
          end
        rescue StandardError => e
          render json: { success: false, error: e.message }, status: :internal_server_error
        end

        # 通過 email 分配教師到學校
        def assign_teacher_by_email
          @school = School.find_by(code: params[:code])
          return render json: { success: false, error: '找不到指定的學校' }, status: :not_found unless @school

          @academic_year = @school.school_academic_years.find_by(name: params[:academic_year_name])
          return render json: { success: false, error: '找不到指定的學年' }, status: :not_found unless @academic_year

          @user = GeneralUser.find_by(email: params[:email])
          return render json: { success: false, error: '找不到指定的用戶' }, status: :not_found unless @user

          # 檢查用戶是否為 AI English 教師
          unless @user.aienglish_user? && @user.meta['aienglish_role'] == 'teacher'
            return render json: { success: false, error: '該用戶不是 AI English 教師' }, status: :unprocessable_entity
          end

          # 創建或更新教師任教記錄
          assignment = TeacherAssignment.find_or_initialize_by(
            general_user: @user,
            school_academic_year: @academic_year
          )

          if assignment.new_record?
            assignment.department = params[:department]
            assignment.position = params[:position]
            assignment.status = :active
            assignment.meta = {
              teaching_subjects: [],
              class_teacher_of: nil,
              additional_duties: []
            }
          end

          # 嘗試保存記錄，如果驗證失敗則直接返回錯誤
          if assignment.save
            render json: { success: true, message: '教師分配成功', assignment: }, status: :ok
          else
            # 直接返回模型驗證錯誤
            render json: { success: false, error: assignment.errors.full_messages.join(', ') },
                   status: :unprocessable_entity
          end
        rescue StandardError => e
          render json: { success: false, error: e.message }, status: :internal_server_error
        end

        # 通過 ai_english_user_id 分配學生到學校
        def assign_student_by_id
          @school = School.find_by(code: params[:code])
          return render json: { success: false, error: '找不到指定的學校' }, status: :not_found unless @school

          @academic_year = @school.school_academic_years.find_by(name: params[:academic_year_name])
          return render json: { success: false, error: '找不到指定的學年' }, status: :not_found unless @academic_year

          @user = GeneralUser.find_by(id: params[:ai_english_user_id])
          return render json: { success: false, error: '找不到指定的用戶' }, status: :not_found unless @user

          # 檢查用戶是否為 AI English 學生
          unless @user.aienglish_user? && @user.meta['aienglish_role'] != 'teacher'
            return render json: { success: false, error: '該用戶不是 AI English 學生' }, status: :unprocessable_entity
          end

          # 創建或更新學生註冊記錄
          enrollment = StudentEnrollment.find_or_initialize_by(
            general_user: @user,
            school_academic_year: @academic_year
          )

          if enrollment.new_record?
            enrollment.class_name = @user.banbie.presence || '未分配'
            enrollment.class_number = @user.class_no.presence || '未分配'
            enrollment.status = :active
          end

          # 嘗試保存記錄，如果驗證失敗會被rescue捕獲
          if enrollment.save
            # 更新該用戶的所有未完成的 EssayGrading 記錄
            update_essay_gradings(@user, @school, @academic_year, enrollment)
            render json: { success: true, message: '學生分配成功', enrollment: }, status: :ok
          else
            # 直接返回模型驗證錯誤
            render json: { success: false, error: enrollment.errors.full_messages.join(', ') },
                   status: :unprocessable_entity
          end
        rescue StandardError => e
          render json: { success: false, error: e.message }, status: :internal_server_error
        end

        # 通過 ai_english_user_id 分配教師到學校
        def assign_teacher_by_id
          @school = School.find_by(code: params[:code])
          return render json: { success: false, error: '找不到指定的學校' }, status: :not_found unless @school

          @academic_year = @school.school_academic_years.find_by(name: params[:academic_year_name])
          return render json: { success: false, error: '找不到指定的學年' }, status: :not_found unless @academic_year

          @user = GeneralUser.find_by(id: params[:ai_english_user_id])
          return render json: { success: false, error: '找不到指定的用戶' }, status: :not_found unless @user

          # 檢查用戶是否為 AI English 教師
          unless @user.aienglish_user? && @user.meta['aienglish_role'] == 'teacher'
            return render json: { success: false, error: '該用戶不是 AI English 教師' }, status: :unprocessable_entity
          end

          # 創建或更新教師任教記錄
          assignment = TeacherAssignment.find_or_initialize_by(
            general_user: @user,
            school_academic_year: @academic_year
          )

          if assignment.new_record?
            assignment.department = params[:department]
            assignment.position = params[:position]
            assignment.status = :active
            assignment.meta = {
              teaching_subjects: [],
              class_teacher_of: nil,
              additional_duties: []
            }
          end

          # 嘗試保存記錄，如果驗證失敗則直接返回錯誤
          if assignment.save
            render json: { success: true, message: '教師分配成功', assignment: }, status: :ok
          else
            # 直接返回模型驗證錯誤
            render json: { success: false, error: assignment.errors.full_messages.join(', ') },
                   status: :unprocessable_entity
          end
        rescue StandardError => e
          render json: { success: false, error: e.message }, status: :internal_server_error
        end

        # GET /admin/v1/schools/:code/academic_years/:academic_year_id/students
        # 獲取指定學年的所有學生
        # @param code [String] 學校代碼
        # @param academic_year_id [Integer] 學年ID
        # @param page [Integer] 可選，頁碼
        # @param per_page [Integer] 可選，每頁數量
        # @param q [String] 可選，搜尋關鍵字 (姓名或Email)
        # @return [JSON] 學生列表
        def academic_year_students
          # 查找指定學年
          academic_year = @school.school_academic_years.find_by(id: params[:academic_year_id])

          unless academic_year
            return render json: { status: 'error', errors: ["找不到學年ID: #{params[:academic_year_id]}"] },
                          status: :not_found
          end

          # 基礎查詢: 獲取學生註冊記錄，預載入用戶，並排除教師
          enrollments_query = academic_year.student_enrollments
                                           .includes(:general_user)
                                           .joins(:general_user)
                                           .where("general_users.meta->>'aienglish_role' != 'teacher'")

          # 搜尋功能 (姓名或Email)
          if params[:q].present?
            search_term = "%#{params[:q].downcase}%"
            enrollments_query = enrollments_query.where(
              'LOWER(general_users.nickname) LIKE :search OR LOWER(general_users.email) LIKE :search',
              search: search_term
            )
          end

          # 排序
          enrollments_query = enrollments_query.order('student_enrollments.class_name ASC NULLS LAST, student_enrollments.class_number ASC NULLS LAST')

          # 分頁處理
          @enrollments = enrollments_query.page(params[:page] || 1).per(params[:per_page] || 20)

          render json: {
            status: 'success',
            data: {
              academic_year: {
                id: academic_year.id,
                name: academic_year.name,
                status: academic_year.status
              },
              students: @enrollments.map { |enrollment| student_info(enrollment) },
              meta: pagination_meta(@enrollments)
            }
          }
        # 捕捉可能的其他錯誤
        rescue StandardError => e
          Rails.logger.error("Error fetching academic year students: #{e.message}")
          Rails.logger.error(e.backtrace.join("\n"))
          render json: { status: 'error', errors: ['處理請求時發生內部錯誤'] }, status: :internal_server_error
        end

        # GET /admin/v1/schools/:code/academic_years/:academic_year_id/classes/:class_name/students
        # 獲取指定班級的所有學生
        # @param code [String] 學校代碼
        # @param academic_year_id [String] 學年ID
        # @param class_name [String] 班級名稱
        # @return [JSON] 學生列表
        def class_students
          # 查找指定學年
          academic_year = @school.school_academic_years.find(params[:academic_year_id])

          # 獲取班級學生列表（帶分頁）
          # 1. 只獲取指定班級的 AI English 學生（排除教師）
          # 2. 按班號排序
          # 3. 預加載關聯數據以提高性能
          @enrollments = academic_year.student_enrollments
                                      .includes(:general_user)
                                      .joins(:general_user)
                                      .where(class_name: params[:class_name])
                                      .where("general_users.meta->>'aienglish_role' != 'teacher'")
                                      .order('student_enrollments.class_number ASC NULLS LAST')

          # 分頁處理
          @enrollments = @enrollments.page(params[:page] || 1).per(params[:per_page] || 20)

          render json: {
            status: 'success',
            data: {
              academic_year: {
                id: academic_year.id,
                name: academic_year.name,
                status: academic_year.status
              },
              class_name: params[:class_name],
              students: @enrollments.map { |enrollment| student_info(enrollment) },
              meta: pagination_meta(@enrollments)
            }
          }
        rescue ActiveRecord::RecordNotFound
          render json: { status: 'error', error: '找不到指定的學年' }, status: :not_found
        rescue StandardError => e
          render json: { status: 'error', error: e.message }, status: :internal_server_error
        end

        # GET /admin/v1/schools/:code/academic_years/:academic_year_id/teachers
        # 獲取指定學年的所有教師
        # @param code [String] 學校代碼
        # @param academic_year_id [Integer] 學年ID
        # @param page [Integer] 可選，頁碼
        # @param per_page [Integer] 可選，每頁數量
        # @param q [String] 可選，搜尋關鍵字 (姓名或Email)
        # @return [JSON] 教師列表
        def academic_year_teachers
          # 查找指定學年
          academic_year = @school.school_academic_years.find_by(id: params[:academic_year_id])

          unless academic_year
            return render json: { status: 'error', errors: ["找不到學年ID: #{params[:academic_year_id]}"] },
                          status: :not_found
          end

          # 基礎查詢: 獲取教師分配記錄，預載入用戶，並篩選教師角色
          assignments_query = academic_year.teacher_assignments
                                           .includes(:general_user)
                                           .joins(:general_user)
                                           .where("general_users.meta->>'aienglish_role' = 'teacher'")

          # 搜尋功能 (姓名或Email)
          if params[:q].present?
            search_term = "%#{params[:q].downcase}%"
            assignments_query = assignments_query.where(
              'LOWER(general_users.nickname) LIKE :search OR LOWER(general_users.email) LIKE :search',
              search: search_term
            )
          end

          # 排序
          assignments_query = assignments_query.order('teacher_assignments.department ASC NULLS LAST, teacher_assignments.position ASC NULLS LAST')

          # 分頁處理
          @assignments = assignments_query.page(params[:page] || 1).per(params[:per_page] || 20)

          render json: {
            status: 'success',
            data: {
              academic_year: {
                id: academic_year.id,
                name: academic_year.name,
                status: academic_year.status
              },
              teachers: @assignments.map { |assignment| teacher_info(assignment) },
              meta: pagination_meta(@assignments)
            }
          }
        rescue ActiveRecord::RecordNotFound
          # 如果 find_by 返回 nil，上面的檢查會處理。這裡捕捉 find (如果未來改用 find)
          render json: { status: 'error', errors: ["找不到學年ID: #{params[:academic_year_id]}"] }, status: :not_found
        rescue StandardError => e
          Rails.logger.error("Error fetching academic year teachers: #{e.message}")
          Rails.logger.error(e.backtrace.join("\n"))
          render json: { status: 'error', errors: ['處理請求時發生內部錯誤'] }, status: :internal_server_error
        end

        # GET /admin/v1/schools/:code/academic_years/:academic_year_id/departments/:department/teachers
        # 獲取指定部門的所有教師
        # @param code [String] 學校代碼
        # @param academic_year_id [String] 學年ID
        # @param department [String] 部門名稱
        # @return [JSON] 教師列表
        def department_teachers
          # 查找指定學年
          academic_year = @school.school_academic_years.find(params[:academic_year_id])

          # 獲取部門教師列表（帶分頁）
          # 1. 只獲取指定部門的 AI English 教師
          # 2. 按職位排序
          # 3. 預加載關聯數據以提高性能
          @assignments = academic_year.teacher_assignments
                                      .includes(:general_user)
                                      .joins(:general_user)
                                      .where(department: params[:department])
                                      .where("general_users.meta->>'aienglish_role' = 'teacher'")
                                      .order('teacher_assignments.position ASC NULLS LAST')

          # 分頁處理
          @assignments = @assignments.page(params[:page] || 1).per(params[:per_page] || 20)

          render json: {
            status: 'success',
            data: {
              academic_year: {
                id: academic_year.id,
                name: academic_year.name,
                status: academic_year.status
              },
              department: params[:department],
              teachers: @assignments.map { |assignment| teacher_info(assignment) },
              meta: pagination_meta(@assignments)
            }
          }
        rescue ActiveRecord::RecordNotFound
          render json: { status: 'error', error: '找不到指定的學年' }, status: :not_found
        rescue StandardError => e
          render json: { status: 'error', error: e.message }, status: :internal_server_error
        end

        # GET /admin/v1/schools/statistics
        # 獲取學校管理系統儀表板統計信息
        # @param date_range [String] 可選的日期範圍過濾，格式為 "YYYY-MM-DD,YYYY-MM-DD"
        # @param school_id [Integer] 可選的學校ID過濾
        # @param academic_year [String] 可選的學年名稱過濾
        # @return [JSON] 儀表板統計數據
        def statistics
          service = Schools::DashboardStatsGenerator.new(
            date_range: params[:date_range],
            school_id: params[:school_id],
            academic_year: params[:academic_year]
          )

          render json: {
            status: 'success',
            code: 200,
            data: service.generate,
            meta: {
              generated_at: Time.current.iso8601,
              filtered_by: {
                date_range: params[:date_range],
                school_id: params[:school_id],
                academic_year: params[:academic_year]
              }
            }
          }
        end

        # POST /admin/v1/schools/:code/promote_students
        # 批量升班
        # @param code [String] 學校代碼
        # @param source_academic_year_id [String] 源學年ID
        # @param target_academic_year_id [String] 目標學年ID
        # @param promotion_rules [Hash] 升班規則
        # @param update_existing [Boolean] 是否更新已存在的記錄
        # @return [JSON] 升班結果
        def promote_students
          @school = School.find_by(code: params[:code])
          return render json: { success: false, error: '找不到指定的學校' }, status: :not_found unless @school

          begin
            source_year = @school.school_academic_years.find(params[:source_academic_year_id])
            target_year = @school.school_academic_years.find(params[:target_academic_year_id])

            # 檢查目標學年是否為活躍狀態
            unless target_year.active?
              return render json: {
                success: false,
                error: '目標學年必須為活躍狀態'
              }, status: :unprocessable_entity
            end

            # 確保只傳遞必要的參數
            service = Schools::BulkClassPromotion.new(
              @school,
              source_year,
              target_year,
              promotion_rules_params
            )

            if service.execute
              render json: {
                success: true,
                message: '批量升班成功',
                data: {
                  total_processed: service.total_processed,
                  success_count: service.success_count,
                  failed_count: service.failed_count,
                  errors: service.promotion_errors
                }
              }
            else
              render json: {
                success: false,
                error: service.errors.full_messages.join(', ')
              }, status: :unprocessable_entity
            end
          rescue ActiveRecord::RecordNotFound
            render json: { success: false, error: '找不到指定的學年' }, status: :not_found
          rescue StandardError => e
            # 添加詳細的錯誤日誌和回溯信息
            Rails.logger.error("批量升班失敗: #{e.message}")
            Rails.logger.error(e.backtrace.join("\n"))
            render json: { success: false, error: e.message }, status: :internal_server_error
          end
        end

        # POST /admin/v1/schools/:code/update_assignments_academic_year
        # 手動更新作業記錄的學年信息
        # @param code [String] 學校代碼
        # @param academic_year_id [String] 學年ID
        # @param date_range [Hash] 日期範圍
        # @param class_name [String] 可選的班級名稱過濾
        # @return [JSON] 更新結果
        def update_assignments_academic_year
          @school = School.find_by(code: params[:code])
          return render json: { success: false, error: '找不到指定的學校' }, status: :not_found unless @school

          begin
            @academic_year = @school.school_academic_years.find(params[:academic_year_id])

            # 獲取日期範圍
            date_range = params[:date_range] || {}
            start_date = date_range[:start_date].present? ? Date.parse(date_range[:start_date]) : 30.days.ago.to_date
            end_date = date_range[:end_date].present? ? Date.parse(date_range[:end_date]) : Date.today

            # 構建查詢
            query = EssayGrading.where(
              created_at: start_date.beginning_of_day..end_date.end_of_day,
              submission_school_id: @school.id
            )

            # 如果指定了班級，則添加過濾條件
            query = query.where(submission_class_name: params[:class_name]) if params[:class_name].present?

            # 更新作業記錄
            count = query.update_all(
              submission_academic_year_id: @academic_year.id
            )

            render json: {
              success: true,
              message: "已更新 #{count} 個作業記錄",
              data: { count: }
            }
          rescue ActiveRecord::RecordNotFound
            render json: { success: false, error: '找不到指定的學年' }, status: :not_found
          rescue StandardError => e
            render json: { success: false, error: e.message }, status: :internal_server_error
          end
        end

        # PUT /admin/v1/schools/:code/enrollments/:enrollment_id
        # 更新學生註冊信息
        def update_enrollment
          @school = School.find_by(code: params[:code])
          return render json: { success: false, error: '找不到指定的學校' }, status: :not_found unless @school

          begin
            enrollment = StudentEnrollment.find(params[:enrollment_id])

            # 確保註冊記錄屬於該學校
            unless enrollment.school_academic_year.school_id == @school.id
              return render json: { success: false, error: '該註冊記錄不屬於指定學校' }, status: :forbidden
            end

            if enrollment.update(enrollment_params)
              render json: {
                success: true,
                message: '成功更新學生註冊信息',
                data: student_info(enrollment)
              }
            else
              render json: {
                success: false,
                error: enrollment.errors.full_messages.join(', ')
              }, status: :unprocessable_entity
            end
          rescue ActiveRecord::RecordNotFound
            render json: { success: false, error: '找不到指定的註冊記錄' }, status: :not_found
          rescue StandardError => e
            render json: { success: false, error: e.message }, status: :internal_server_error
          end
        end

        private

        # 設置當前學校
        # @param code [String] 學校代碼
        def set_school
          @school = School.find_by(code: params[:code])

          return if @school

          render json: {
            status: 'error',
            errors: ["找不到學校代碼: #{params[:code]}"]
          }, status: :not_found
        end

        # 學校參數白名單
        # @return [ActionController::Parameters] 過濾後的參數
        def school_params
          params.require(:school).permit(
            :name, :code, :status, :address,
            :contact_email, :contact_phone,
            :region, :timezone,
            :school_type, :curriculum_type,
            :academic_system, :logo,
            custom_settings: {},
            academic_years: %i[name status start_year start_month end_month]
          )
        end

        # 批量學生分配參數
        # @return [ActionController::Parameters] 過濾後的參數
        def bulk_students_params
          params.require(:assignments).map do |assignment|
            assignment.permit(:school_code, :academic_year_name, :email_patterns)
          end
        end

        # 批量教師分配參數
        # @return [ActionController::Parameters] 過濾後的參數
        def bulk_teachers_params
          params.require(:assignments).map do |assignment|
            assignment.permit(:school_code, :academic_year_name, :email_patterns, :department, :position)
          end
        end

        # 學校序列化
        # @param school [School] 學校對象
        # @return [Hash] 序列化後的學校數據
        def school_serializer(school)
          {
            id: school.id,
            name: school.name,
            code: school.code,
            status: school.status,
            address: school.address,
            contact_email: school.contact_email,
            contact_phone: school.contact_phone,
            timezone: school.timezone,
            logo: {
              has_logo: school.logo.attached?,
              original_url: school.logo_url,
              thumbnail_url: school.logo_thumbnail_url,
              small_url: school.logo_small_url,
              large_url: school.logo_large_url,
              square_url: school.logo_square_url
            },
            meta: {
              region: school.meta['region'],
              school_type: school.meta['school_type'],
              curriculum_type: school.meta['curriculum_type'],
              academic_system: school.meta['academic_system'],
              custom_settings: school.meta['custom_settings'] || {}
            },
            academic_years: school.school_academic_years.map do |academic_year|
              {
                id: academic_year.id,
                name: academic_year.name,
                status: academic_year.status,
                start_date: academic_year.start_date,
                end_date: academic_year.end_date
              }
            end,
            created_at: school.created_at,
            updated_at: school.updated_at
          }
        end

        # 分頁元數據
        # @param collection [ActiveRecord::Relation] 分頁後的集合
        # @return [Hash] 分頁元數據
        def pagination_meta(collection)
          {
            current_page: collection.current_page,
            next_page: collection.next_page,
            prev_page: collection.prev_page,
            total_pages: collection.total_pages,
            total_count: collection.total_count
          }
        end

        # 學年序列化
        # @param academic_year [SchoolAcademicYear] 學年對象
        # @return [Hash] 序列化後的學年數據
        def academic_year_serializer(academic_year)
          # 獲取學生統計數據
          student_stats = {
            total: academic_year.student_enrollments.count,
            active: academic_year.student_enrollments.where(status: :active).count,
            graduated: academic_year.student_enrollments.where(status: :graduated).count,
            transferred: academic_year.student_enrollments.where(status: :transferred).count,
            withdrawn: academic_year.student_enrollments.where(status: :withdrawn).count,
            promoted: academic_year.student_enrollments.where(status: :promoted).count
          }

          # 獲取教師統計數據
          teacher_stats = {
            total: academic_year.teacher_assignments.count,
            active: academic_year.teacher_assignments.where(status: :active).count,
            resigned: academic_year.teacher_assignments.where(status: :resigned).count,
            transferred: academic_year.teacher_assignments.where(status: :transferred).count,
            sabbatical: academic_year.teacher_assignments.where(status: :sabbatical).count
          }

          {
            id: academic_year.id,
            name: academic_year.name,
            status: academic_year.status,
            school_id: academic_year.school_id,
            school_name: academic_year.school.name,
            school_code: academic_year.school.code,
            start_date: academic_year.start_date,
            end_date: academic_year.end_date,
            # 保留簡單計數以保持向後兼容性
            student_count: student_stats[:total],
            teacher_count: teacher_stats[:total],
            # 添加詳細的學生統計信息
            student_stats:,
            # 添加詳細的教師統計信息
            teacher_stats:,
            created_at: academic_year.created_at,
            updated_at: academic_year.updated_at
          }
        end

        # 更新用戶的 EssayGrading 記錄
        def update_essay_gradings(user, school, academic_year, enrollment)
          # 只更新最近30天的作業記錄
          recent_date = 30.days.ago
          user.essay_gradings
              .where('created_at > ?', recent_date)
              .find_each do |grading|
            grading.update!(
              submission_class_name: enrollment.class_name,
              submission_class_number: enrollment.class_number,
              submission_school_id: school.id,
              submission_academic_year_id: academic_year.id
            )
          end
        end

        # 學生詳細信息
        # @param enrollment [StudentEnrollment] 註冊記錄
        # @return [Hash] 學生信息
        def student_info(enrollment)
          student = enrollment.general_user
          {
            id: student.id,
            email: student.email,
            nickname: student.nickname,
            banbie: student.banbie,
            class_no: student.class_no,
            status: enrollment.status,
            class_name: enrollment.class_name,
            class_number: enrollment.class_number,
            created_at: enrollment.created_at,
            updated_at: enrollment.updated_at
          }
        end

        # 教師詳細信息
        # @param assignment [TeacherAssignment] 任教記錄
        # @return [Hash] 教師信息
        def teacher_info(assignment)
          teacher = assignment.general_user
          {
            id: teacher.id,
            email: teacher.email,
            nickname: teacher.nickname,
            department: assignment.department,
            position: assignment.position,
            status: assignment.status,
            teaching_subjects: assignment.meta['teaching_subjects'] || [],
            class_teacher_of: assignment.meta['class_teacher_of'],
            additional_duties: assignment.meta['additional_duties'] || [],
            created_at: assignment.created_at,
            updated_at: assignment.updated_at
          }
        end

        # 升班規則參數
        # @return [ActionController::Parameters] 過濾後的參數
        def promotion_rules_params
          params.require(:promotion_rules).permit(
            class_rules: {},
            number_rules: {}
          )
        end

        # 學生註冊參數
        # @return [ActionController::Parameters] 過濾後的參數
        def enrollment_params
          params.require(:enrollment).permit(:class_name, :class_number, :status)
        end
      end
    end
  end
end
