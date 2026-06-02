# frozen_string_literal: true

module Api
  module Admin
    module V1
      class EssayGradingsController < AdminApiController
        # include AdminAuthenticator

        before_action :set_essay_grading, only: [:show, :rerun_workflow, :rerun_supplement_practice_workflow]
        # before_action :check_stopped_status, only: [:rerun_workflow]

        def speaking_times_data
          # 支持的时间范围参数: week(默认), month, year
          range = params[:range] || 'week'
          
          # 根据参数确定时间范围
          start_date = case range
                      when 'year'
                        1.year.ago
                      when 'month'
                        1.month.ago
                      else # 默认为 week
                        1.week.ago
                      end
          
          # 查询符合条件的EssayGrading记录，只选择所需的字段
          # 使用PostgreSQL的JSON查询功能提取speaking_pronunciation_sentences数组中的speaking_times
          essay_gradings = EssayGrading  
                          .joins(:essay_assignment)
                          .where(essay_assignments: { category: 'speaking_pronunciation' })
                          .where('essay_gradings.created_at >= ?', start_date)  
                          .where("essay_gradings.grading ? 'speaking_pronunciation_sentences'")
                          .select("essay_gradings.id, essay_gradings.created_at, 
                                  (SELECT jsonb_agg((elem->>'speaking_times')::integer) 
                                   FROM jsonb_array_elements(essay_gradings.grading->'speaking_pronunciation_sentences') AS elem) AS speaking_times_array")
          
          # 根据统计范围确定分组方式
          daily_speaking_times = {}
          
          essay_gradings.each do |eg|
            # 根据范围确定分组键
            group_key = case range
                       when 'year'
                         # 按月分组
                         eg.created_at.beginning_of_month.to_date
                       else
                         # 按天分组
                         eg.created_at.to_date
                       end
            
            # 初始化该分组的计数
            daily_speaking_times[group_key] ||= 0
            
            # 从数据库查询出的speaking_times_array中提取speaking_times值并累加
            if eg.speaking_times_array && eg.speaking_times_array.is_a?(Array)
              # 遍历每个speaking_times值并累加
              eg.speaking_times_array.each do |speaking_times|
                daily_speaking_times[group_key] += speaking_times.to_i || 1 # 默认为1
              end
            end
          end
          
          # 格式化结果
          result = daily_speaking_times.map do |date, count|
            {
              date: date,
              speaking_times: count
            }
          end
          
          # 按日期排序
          result.sort_by! { |item| item[:date] }
          
          render json: { 
            success: true, 
            range: range,
            data: result
          }, status: :ok
        end
                
        # GET /api/admin/v1/essay_gradings/pending_or_stopped
        # Optional filter: ?status=pending or ?status=stopped
        def pending_or_stopped
          base_scope = EssayGrading.pending_or_stopped
          meta_counts = pending_or_stopped_meta_counts(base_scope)

          filtered_scope = apply_pending_or_stopped_status_filter(base_scope)
          return if performed?

          essay_gradings = filtered_scope
                           .includes(:essay_assignment, :general_user)
                           .submitted_recent_first

          render json: {
            success: true,
            meta: meta_counts.merge(filtered_status: params[:status].presence),
            essay_gradings: essay_gradings.map { |grading| pending_or_stopped_grading_json(grading) }
          }, status: :ok
        end

        # GET /api/admin/v1/essay_gradings/:id
        def show
          # 预加载 essay_assignment 关联以获取 category 信息
          @essay_grading = EssayGrading.includes(:essay_assignment, :general_user).find(params[:id])
                  
          grading_json = begin
            JSON.parse(@essay_grading.grading['data']['text'])
          rescue StandardError
            {}
          end
                  
          scores = grading_json.each_with_object({}) do |(key, value), result|
            next unless key.start_with?('Criterion') && value.is_a?(Hash)
                    
            value.each do |criterion_key, criterion_value|
              # 排除不需要的键
              result[criterion_key] = criterion_value unless ['Full Score', 'explanation'].include?(criterion_key)
            end
          end
                  
          if @essay_grading.category == 'comprehension'
            score = @essay_grading.grading.dig('comprehension', 'score')
            full_score = @essay_grading.grading.dig('comprehension', 'full_score')
          elsif @essay_grading.category == 'speaking_pronunciation'
            score = @essay_grading['score']
            full_score = 100
          else
            score = @essay_grading.grading['score']
            full_score = @essay_grading.grading['full_score']
          end
                  
          render json: {
            success: true,
            data: {
              essay_grading: {
                id: @essay_grading.id,
                topic: @essay_grading.topic,
                created_at: @essay_grading.created_at,
                updated_at: @essay_grading.updated_at,
                status: @essay_grading.status,
                number_of_suggestion: @essay_grading.grading['number_of_suggestion'],
                questions_count: @essay_grading.grading.dig('comprehension', 'questions_count'),
                full_score: full_score,
                score: score,
                scores: scores,
                grading: @essay_grading.grading,
                general_context: @essay_grading.general_context,
                essay: @essay_grading.essay,
                meta: @essay_grading.meta,
                using_time: @essay_grading.using_time,
                file: @essay_grading.file.attached? ? @essay_grading.file.url : nil,
                submission_class_name: @essay_grading.submission_class_name,
                submission_class_number: @essay_grading.submission_class_number,
                general_user: {
                  id: @essay_grading.general_user.id,
                  nickname: @essay_grading.general_user.nickname,
                  class_name: @essay_grading.general_user.banbie,
                  class_no: @essay_grading.general_user.class_no
                },
                essay_assignment: {
                  id: @essay_grading.essay_assignment.id,
                  title: @essay_grading.essay_assignment.title,
                  category: @essay_grading.essay_assignment.category,
                  remark: @essay_grading.essay_assignment.remark,
                  answer_visible: @essay_grading.essay_assignment.answer_visible,
                  newsfeed_id: @essay_grading.essay_assignment.newsfeed_id,
                  meta: @essay_grading.essay_assignment.meta,
                  rubric: @essay_grading.essay_assignment.rubric,
                  created_at: @essay_grading.essay_assignment.created_at,
                  updated_at: @essay_grading.essay_assignment.updated_at
                }
              }
            }
          }, status: :ok
        end
        
        # POST /api/admin/v1/essay_gradings/:id/rerun_workflow
        def rerun_workflow
          begin
            @essay_grading.rerun_workflow
            render json: { 
              success: true, 
              message: 'Workflow rerun successfully',
              essay_grading: @essay_grading
            }, status: :ok
          rescue StandardError => e
            render json: { 
              success: false, 
              message: "Failed to rerun workflow: #{e.message}"
            }, status: :internal_server_error
          end
        end
        # POST /api/admin/v1/essay_gradings/:id/rerun_supplement_practice_workflow
        def rerun_supplement_practice_workflow
          begin
            @essay_grading.run_supplement_practice_workflow
            render json: { 
              success: true, 
              message: 'Supplement practice workflow rerun successfully',
              essay_grading: @essay_grading
            }, status: :ok
          rescue StandardError => e
            render json: { 
              success: false, 
              message: "Failed to rerun supplement practice workflow: #{e.message}"
            }, status: :internal_server_error
          end
        end

        # POST /api/admin/v1/essay_gradings/bulk_rerun_workflow
        # Body: { "ids": ["uuid-1", "uuid-2"] }，最多 5 条，逐条 rerun_workflow
        def bulk_rerun_workflow
          ids = parse_bulk_ids!
          return if performed?

          result = ::Admin::EssayGradings::BulkRerunWorkflowService.new(ids: ids).call
          render json: result, status: :ok
        end

        # PATCH /api/admin/v1/essay_gradings/bulk_update_status
        # Body: { "ids": ["uuid-1"], "status": "draft" }，首版仅支持改为 draft
        def bulk_update_status
          ids = parse_bulk_ids!
          return if performed?

          target_status = params[:status].to_s.presence
          if target_status.blank?
            render json: { success: false, error: 'status is required' }, status: :bad_request
            return
          end

          result = ::Admin::EssayGradings::BulkUpdateStatusService.new(ids: ids, status: target_status).call
          render json: result, status: :ok
        rescue ArgumentError => e
          render json: { success: false, error: e.message }, status: :bad_request
        end

        private

        # 校验并规范化批量 ids 参数；失败时 render 并返回 nil
        def parse_bulk_ids!
          ::Admin::EssayGradings::BulkIdsValidator.normalize!(params[:ids])
        rescue ::Admin::EssayGradings::BulkIdsValidator::ValidationError => e
          status = e.message.include?('exceed') ? :unprocessable_entity : :bad_request
          render json: { success: false, error: e.message }, status: status
          nil
        end

        def set_essay_grading
          @essay_grading = EssayGrading.find(params[:id])
        end

        def check_stopped_status
          unless @essay_grading.stopped?
            render json: {
              success: false,
              message: 'Essay grading is not in stopped status'
            }, status: :unprocessable_entity
          end
        end

        def apply_pending_or_stopped_status_filter(scope)
          return scope if params[:status].blank?

          status_param = params[:status].to_s.downcase
          status_param = 'stopped' if status_param == 'stop'

          allowed_statuses = %w[pending stopped]
          unless allowed_statuses.include?(status_param)
            render json: {
              success: false,
              error: "Invalid status. Valid values are: #{allowed_statuses.join(', ')}"
            }, status: :bad_request
            return nil
          end

          scope.where(status: status_param)
        end

        def pending_or_stopped_meta_counts(base_scope)
          pending_count = base_scope.pending.count
          stopped_count = base_scope.stopped.count

          {
            total: pending_count + stopped_count,
            pending: pending_count,
            stopped: stopped_count
          }
        end

        def pending_or_stopped_grading_json(grading)
          assignment = grading.essay_assignment
          user = grading.general_user
          grading_meta = grading.meta.is_a?(Hash) ? grading.meta : {}

          {
            id: grading.id,
            topic: grading.topic,
            status: grading.status,
            created_at: grading.created_at,
            updated_at: grading.updated_at,
            using_time: grading.using_time,
            submission_class_name: grading.submission_class_name,
            submission_class_number: grading.submission_class_number,
            last_grading_error: grading_meta['last_grading_error'],
            grading_failure: grading_meta['grading_failure'],
            grading_errors: grading_meta['grading_errors'],
            general_user: {
              id: user.id,
              nickname: user.nickname,
              email: user.email,
              class_name: user.banbie,
              class_no: user.class_no
            },
            essay_assignment: assignment && {
              id: assignment.id,
              code: assignment.code,
              assignment: assignment.assignment,
              title: assignment.title,
              topic: assignment.topic,
              category: assignment.category,
              remark: assignment.remark
            }
          }
        end
      end
    end
  end
end