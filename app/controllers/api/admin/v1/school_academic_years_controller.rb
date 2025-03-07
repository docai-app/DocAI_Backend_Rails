module Api
  module Admin
    module V1
      # 學校學年管理控制器
      # 提供學年創建、更新、刪除功能的 API 端點
      class SchoolAcademicYearsController < AdminApiController
        before_action :set_academic_year, only: %i[show update destroy]

        # GET /admin/v1/school_academic_years/:id
        # 獲取特定學年的詳細信息
        # @param id [Integer] 學年ID
        # @return [JSON] 學年的詳細信息
        def show
          render json: {
            status: 'success',
            data: academic_year_serializer(@academic_year)
          }
        end

        # POST /admin/v1/school_academic_years
        # 創建新學年
        # @param school_code [String] 學校代碼
        # @param academic_year [Hash] 學年信息
        # @return [JSON] 新創建的學年信息
        def create
          school = School.find_by(code: params[:school_code])

          unless school
            return render json: {
              status: 'error',
              errors: ["找不到學校代碼: #{params[:school_code]}"]
            }, status: :not_found
          end

          service = Schools::AcademicYearCreator.new(school, academic_year_params)

          if service.execute
            render json: {
              status: 'success',
              message: "成功創建學年: #{service.academic_year.name}",
              data: academic_year_serializer(service.academic_year)
            }, status: :created
          else
            render json: {
              status: 'error',
              errors: service.errors.full_messages
            }, status: :unprocessable_entity
          end
        end

        # PUT/PATCH /admin/v1/school_academic_years/:id
        # 更新學年信息
        # @param id [Integer] 學年ID
        # @param academic_year [Hash] 更新的學年信息
        # @return [JSON] 更新後的學年信息
        def update
          service = Schools::AcademicYearUpdater.new(@academic_year, academic_year_params)

          if service.execute
            render json: {
              status: 'success',
              message: "成功更新學年: #{@academic_year.name}",
              data: academic_year_serializer(@academic_year)
            }
          else
            render json: {
              status: 'error',
              errors: service.errors.full_messages
            }, status: :unprocessable_entity
          end
        end

        # DELETE /admin/v1/school_academic_years/:id
        # 刪除學年
        # @param id [Integer] 學年ID
        # @return [JSON] 操作結果
        def destroy
          # 檢查是否有依賴關係（學生註冊或教師分配）
          if @academic_year.student_enrollments.exists? || @academic_year.teacher_assignments.exists?
            return render json: {
              status: 'error',
              errors: ['該學年有關聯的學生註冊或教師分配記錄，無法刪除']
            }, status: :unprocessable_entity
          end

          if @academic_year.destroy
            render json: {
              status: 'success',
              message: "學年 #{@academic_year.name} 已成功刪除"
            }
          else
            render json: {
              status: 'error',
              errors: @academic_year.errors.full_messages
            }, status: :unprocessable_entity
          end
        end

        private

        # 設置當前學年
        # @param id [Integer] 學年ID
        def set_academic_year
          @academic_year = SchoolAcademicYear.find_by(id: params[:id])

          return if @academic_year

          render json: {
            status: 'error',
            errors: ["找不到學年ID: #{params[:id]}"]
          }, status: :not_found
        end

        # 學年參數白名單
        # @return [ActionController::Parameters] 過濾後的參數
        def academic_year_params
          params.require(:academic_year).permit(
            :name, :status, :start_date, :end_date,
            :start_year, :start_month, :end_month
          )
        end

        # 學年序列化
        # @param academic_year [SchoolAcademicYear] 學年對象
        # @return [Hash] 序列化後的學年數據
        def academic_year_serializer(academic_year)
          {
            id: academic_year.id,
            name: academic_year.name,
            status: academic_year.status,
            school_id: academic_year.school_id,
            school_name: academic_year.school.name,
            school_code: academic_year.school.code,
            start_date: academic_year.start_date,
            end_date: academic_year.end_date,
            student_count: academic_year.student_enrollments.count,
            teacher_count: academic_year.teacher_assignments.count,
            created_at: academic_year.created_at,
            updated_at: academic_year.updated_at
          }
        end
      end
    end
  end
end
