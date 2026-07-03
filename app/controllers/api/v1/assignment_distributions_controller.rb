# frozen_string_literal: true

module Api
  module V1
    class AssignmentDistributionsController < ApiController
      before_action :authenticate_general_user!
      before_action :set_essay_assignment, except: [:distribution_options]
      before_action :ensure_teacher_and_same_school, except: [:distribution_options]
      before_action :ensure_teacher_for_distribution_options, only: [:distribution_options]
      before_action :set_distribution, only: %i[show update destroy]

      # GET /api/v1/essay_assignments/distribution_options
      def distribution_options
        school = current_general_user.get_school
        return render_unauthorized unless school

        academic_year = params[:school_academic_year_id].present? ? 
          SchoolAcademicYear.find_by(id: params[:school_academic_year_id]) :
          school.current_academic_year

        return render_not_found('Academic year not found') unless academic_year

        # 獲取班級列表（優化：使用單一查詢）
        # 確保只查詢 active 狀態的學年，並過濾掉空的 class_name
        # 使用 COUNT(DISTINCT general_user_id) 確保每個學生只被計算一次，避免重複計算
        classes = StudentEnrollment
          .joins(:school_academic_year)
          .where(school_academic_years: { id: academic_year.id })
          .where('school_academic_years.status = ?', SchoolAcademicYear.statuses[:active])
          .where(status: :active)
          .where.not(class_name: [nil, ''])
          .group(:class_name)
          .select('class_name, COUNT(DISTINCT general_user_id) as student_count')
          .map do |e|
            {
              class_name: e.class_name,
              student_count: e.read_attribute('student_count') || e.attributes['student_count'] || 0
            }
          end

        # 獲取學生列表（優化：避免 N+1 查詢）
        # 確保只獲取當前學年的學生，並按 general_user_id 去重
        # 根據模型驗證，同一學年中一個學生應該只有一個記錄，但為了保險起見，使用 uniq 去重
        enrollments = StudentEnrollment
          .includes(:general_user, :school_academic_year)
          .joins(:general_user, :school_academic_year)
          .where(school_academic_years: { id: academic_year.id })
          .where(status: :active)
          .where('school_academic_years.status = ?', SchoolAcademicYear.statuses[:active])
          .order('student_enrollments.general_user_id, student_enrollments.created_at DESC')
        
        # 使用 Hash 按 general_user_id 去重，確保每個學生只返回一次
        # 如果同一學生有多個記錄，選擇最新的（按 created_at DESC 排序）
        unique_enrollments = enrollments.each_with_object({}) do |enrollment, hash|
          user_id = enrollment.general_user_id
          hash[user_id] ||= enrollment
        end.values
        
        students = unique_enrollments.map do |enrollment|
          {
            id: enrollment.general_user.id,
            nickname: enrollment.general_user.nickname,
            email: enrollment.general_user.email,
            class_name: enrollment.class_name,
            class_number: enrollment.general_user.class_no
          }
        end

        render json: {
          success: true,
          options: {
            school_academic_year: {
              id: academic_year.id,
              name: academic_year.name,
              start_date: academic_year.start_date,
              end_date: academic_year.end_date
            },
            classes: classes,
            students: students
          }
        }, status: :ok
      end

      # POST /api/v1/essay_assignments/:essay_assignment_id/distributions
      def create
        school = current_general_user.get_school
        academic_year = school&.current_academic_year

        return render_not_found('School or academic year not found') unless school && academic_year

        # 支援批量創建
        if params[:distributions].present?
          distributions = params[:distributions].map do |dist_params|
            distribution = @essay_assignment.assignment_distributions.build(
              distribution_params(dist_params)
            )
            distribution.school = school
            distribution.school_academic_year = academic_year
            distribution
          end

          saved = distributions.select(&:save)
          failed = distributions.reject(&:persisted?)

          render json: {
            success: failed.empty?,
            distributions: saved.map { |d| distribution_json(d) },
            errors: failed.map { |d| d.errors.full_messages }
          }, status: failed.empty? ? :created : :unprocessable_entity
        else
          distribution = @essay_assignment.assignment_distributions.build(distribution_params)
          distribution.school = school
          distribution.school_academic_year = academic_year

          if distribution.save
            render json: {
              success: true,
              distribution: distribution_json(distribution)
            }, status: :created
          else
            render json: {
              success: false,
              errors: distribution.errors.full_messages
            }, status: :unprocessable_entity
          end
        end
      end

      # GET /api/v1/essay_assignments/:essay_assignment_id/distributions
      def index
        distributions = @essay_assignment.assignment_distributions
                                          .active
                                          .includes(:school_academic_year)
                                          .order(created_at: :desc)

        render json: {
          success: true,
          distributions: distributions.map { |d| distribution_json(d) }
        }, status: :ok
      end

      # GET /api/v1/essay_assignments/:essay_assignment_id/distributions/:id
      def show
        render json: {
          success: true,
          distribution: distribution_json(@distribution, include_students: true)
        }, status: :ok
      end

      # PATCH /api/v1/essay_assignments/:essay_assignment_id/distributions/:id
      def update
        if @distribution.update(distribution_params)
          render json: {
            success: true,
            distribution: distribution_json(@distribution)
          }, status: :ok
        else
          render json: {
            success: false,
            errors: @distribution.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/essay_assignments/:essay_assignment_id/distributions/:id
      def destroy
        if @distribution.cancelled!
          render json: {
            success: true,
            message: 'Distribution cancelled successfully'
          }, status: :ok
        else
          render json: {
            success: false,
            errors: @distribution.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/essay_assignments/:essay_assignment_id/distributions/add_students
      def add_students
        school = current_general_user.get_school
        academic_year = school&.current_academic_year

        return render_not_found('School or academic year not found') unless school && academic_year

        student_ids = params[:student_ids] || []
        deadline = params[:deadline]

        return render json: { success: false, error: 'student_ids and deadline are required' }, 
                      status: :bad_request if student_ids.empty? || deadline.blank?

        # 驗證 deadline 必須大於當前時間
        begin
          # 使用 Time.zone.parse 確保使用應用時區，與 Time.current 保持一致
          deadline_time = Time.zone.parse(deadline)
          unless deadline_time
            return render json: { 
              success: false, 
              error: 'Invalid deadline format' 
            }, status: :bad_request
          end
          
          if deadline_time <= Time.current
            return render json: { 
              success: false, 
              error: 'Deadline must be greater than the current time' 
            }, status: :unprocessable_entity
          end
        rescue ArgumentError => e
          return render json: { 
            success: false, 
            error: 'Invalid deadline format' 
          }, status: :bad_request
        end

        # 驗證學生是否屬於當前學校當前學年
        valid_students = GeneralUser
          .joins(:student_enrollments)
          .where(id: student_ids)
          .where(student_enrollments: { 
            school_academic_year_id: academic_year.id,
            status: :active 
          })
          .distinct

        if valid_students.count != student_ids.count
          return render json: { 
            success: false, 
            error: 'Some students are not in the current school academic year' 
          }, status: :unprocessable_entity
        end

        # 查找已存在的分配記錄
        existing_assignments = @essay_assignment.assignment_student_assignments
                                                 .where(general_user_id: student_ids)
                                                 .pluck(:general_user_id)

        new_student_ids = student_ids - existing_assignments

        return render json: {
          success: true,
          added_count: 0,
          skipped_count: student_ids.count,
          message: 'All students are already assigned'
        }, status: :ok if new_student_ids.empty?

        # 為每個學生創建分配記錄和 AssignmentStudentAssignment
        # 注意：這裡為每個學生創建一個 individual 類型的 distribution
        added_count = 0
        failed_student_ids = []

        new_student_ids.each do |student_id|
          begin
            # 為每個學生創建一個 individual 類型的 distribution
            distribution = @essay_assignment.assignment_distributions.create!(
              school: school,
              school_academic_year: academic_year,
              distribution_type: 'individual',
              target_student_id: student_id,
              deadline: deadline,
              status: :active
            )

            # create_student_assignments 回調會自動創建 AssignmentStudentAssignment
            added_count += 1
          rescue StandardError => e
            Rails.logger.error "Failed to add student #{student_id}: #{e.message}"
            failed_student_ids << student_id
          end
        end

        render json: {
          success: true,
          added_count: added_count,
          skipped_count: existing_assignments.count,
          failed_count: failed_student_ids.count,
          failed_student_ids: failed_student_ids,
          message: "Successfully added #{added_count} students to assignment"
        }, status: added_count > 0 ? :ok : :unprocessable_entity
      end

      # POST /api/v1/essay_assignments/:essay_assignment_id/distributions/remove_students
      def remove_students
        student_ids = params[:student_ids] || []

        return render json: { success: false, error: 'student_ids is required' }, 
                      status: :bad_request if student_ids.empty?

        # 查找要取消的分配記錄
        assignments_to_remove = @essay_assignment.assignment_student_assignments
                                                  .where(general_user_id: student_ids)

        removed_count = assignments_to_remove.count
        not_found_count = student_ids.count - removed_count

        # 獲取相關的 distribution IDs（用於後續清理）
        distribution_ids = assignments_to_remove.pluck(:assignment_distribution_id).uniq

        # 刪除 AssignmentStudentAssignment 記錄
        assignments_to_remove.destroy_all

        # 清理沒有關聯學生的 individual 類型的 distribution
        # 注意：只清理 individual 類型，class_name 類型的 distribution 保留
        @essay_assignment.assignment_distributions
                        .where(id: distribution_ids, distribution_type: 'individual')
                        .where.not(id: AssignmentStudentAssignment.select(:assignment_distribution_id))
                        .destroy_all

        render json: {
          success: true,
          removed_count: removed_count,
          not_found_count: not_found_count,
          message: "Successfully removed #{removed_count} students from assignment"
        }, status: :ok
      end

      private

      def set_essay_assignment
        @essay_assignment = EssayAssignment.find(params[:essay_assignment_id])
      rescue ActiveRecord::RecordNotFound
        render json: { success: false, error: 'EssayAssignment not found' }, status: :not_found
      end

      def set_distribution
        @distribution = @essay_assignment.assignment_distributions.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { success: false, error: 'Distribution not found' }, status: :not_found
      end

      def ensure_teacher_and_same_school
        unless current_general_user.aienglish_role == 'teacher'
          render json: { success: false, error: 'Only teachers can manage distributions' },
                 status: :forbidden
          return
        end

        # school = current_general_user.get_school
        # unless school && assignment_manageable_in_school?(school)
        #   render json: { success: false, error: 'You can only manage distributions in your own school' },
        #          status: :forbidden
        # end
      end

      def assignment_manageable_in_school?(school)
        return true if @essay_assignment.owned_by?(current_general_user) &&
                       @essay_assignment.general_user.get_school&.id == school.id

        @essay_assignment.shared_with?(current_general_user) &&
          @essay_assignment.category_enabled_for?(current_general_user) &&
          @essay_assignment.general_user.get_school&.id == school.id
      end

      def ensure_teacher_for_distribution_options
        unless current_general_user.aienglish_role == 'teacher'
          render json: { success: false, error: 'Only teachers can view distribution options' }, 
                 status: :forbidden
        end
      end

      def distribution_params(params_hash = nil)
        params_to_use = params_hash || params[:distribution] || {}
        params_to_use.permit(
          :distribution_type,
          :target_class_name,
          :target_student_id,
          :deadline,
          :school_academic_year_id
        )
      end

      def distribution_json(distribution, include_students: false)
        json = {
          id: distribution.id,
          distribution_type: distribution.distribution_type,
          target_class_name: distribution.target_class_name,
          target_student_id: distribution.target_student_id,
          deadline: distribution.deadline&.iso8601,
          status: distribution.status,
          assigned_students_count: distribution.assignment_student_assignments.count,
          created_at: distribution.created_at.iso8601,
          updated_at: distribution.updated_at.iso8601
        }

        if include_students
          json[:assigned_students] = distribution.target_students.map do |student|
            {
              id: student.id,
              nickname: student.nickname,
              email: student.email,
              class_name: student.current_enrollment&.class_name,
              class_number: student.class_no
            }
          end
        end

        json
      end

      def render_unauthorized
        render json: { success: false, error: 'Unauthorized' }, status: :unauthorized
      end

      def render_not_found(message = 'Resource not found')
        render json: { success: false, error: message }, status: :not_found
      end
    end
  end
end
