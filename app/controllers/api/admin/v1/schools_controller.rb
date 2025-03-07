module Api
  module Admin
    module V1
      # 學校管理控制器
      # 提供學校創建、列表、分配學生/教師等功能的 API 端點
      class SchoolsController < AdminApiController
        before_action :set_school, only: %i[show update destroy assign_students
                                            assign_teachers student_stats teacher_stats]

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
            :academic_system,
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
            region: school.meta['region'],
            school_type: school.meta['school_type'],
            curriculum_type: school.meta['curriculum_type'],
            academic_system: school.meta['academic_system'],
            custom_settings: school.meta['custom_settings'],
            created_at: school.created_at,
            updated_at: school.updated_at,
            academic_years: school.school_academic_years.map do |year|
              {
                id: year.id,
                name: year.name,
                status: year.status,
                start_date: year.start_date,
                end_date: year.end_date,
                created_at: year.created_at,
                updated_at: year.updated_at
              }
            end
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
      end
    end
  end
end
