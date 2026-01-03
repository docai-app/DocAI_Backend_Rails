# frozen_string_literal: true

module Api
  module Admin
    module V1
      class EssayGradingsController < AdminApiController
        # include AdminAuthenticator

        before_action :set_essay_grading, only: [:rerun_workflow]
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

        private

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
      end
    end
  end
end