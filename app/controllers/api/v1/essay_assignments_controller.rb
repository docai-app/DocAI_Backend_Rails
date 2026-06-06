# frozen_string_literal: true

module Api
  module V1
    class EssayAssignmentsController < ApiController
      before_action :authenticate_general_user!
      before_action :set_essay_assignment, only: %i[update destroy]

      before_action :set_essay_assignment_by_code, only: %i[show_only]
      before_action :aienglish_access, only: %i[show_only]

      def index
        @essay_assignments = current_general_user.essay_assignments
        @essay_assignments = @essay_assignments.where(category: params[:category]) if params[:category].present?

        draft_status = EssayGrading.statuses[:draft]

        select_columns = <<~SQL
          essay_assignments.id,
          essay_assignments.rubric,
          essay_assignments.title,
          essay_assignments.hints,
          essay_assignments.category,
          essay_assignments.answer_visible,
          essay_assignments.topic,
          essay_assignments.created_at,
          essay_assignments.updated_at,
          essay_assignments.code,
          essay_assignments.assignment,
          essay_assignments.meta,
          COUNT(CASE WHEN essay_gradings.status != #{draft_status} THEN 1 END) AS number_of_submission
        SQL

        @essay_assignments = @essay_assignments
                               .left_outer_joins(:essay_gradings)
                               .select(select_columns)
                               .group('essay_assignments.id')
                               .order('essay_assignments.created_at desc')
                               .page(params[:page])
                               .per(params[:count] || 10)

        render json: {
          success: true,
          essay_assignments: @essay_assignments,
          meta: pagination_meta(@essay_assignments)
        }, status: :ok
      end

      def show_only
        # 構建基本響應數據
        assignment_data = @essay_assignment.as_json

        # 添加圖片URL（如果有附件）- IELTS看圖作文功能
        graph_image_url = @essay_assignment.graph_image_url
        if graph_image_url
          assignment_data['graph_image_url'] = graph_image_url
          Rails.logger.info "[EssayAssignments#show_only] Graph image URL generated for assignment #{@essay_assignment.id}"
        else
          Rails.logger.info "[EssayAssignments#show_only] No graph image URL for assignment #{@essay_assignment.id} (attached: #{@essay_assignment.graph_image.attached?})"
        end

        # 添加Sample Essay（只在IELTS Task 1且已生成時）- IELTS功能
        if @essay_assignment.name == 'IELTS Task 1' && @essay_assignment.sample_essay.present?
          assignment_data['sample_essay'] = @essay_assignment.sample_essay
        end

        render json: { success: true, essay_assignment: assignment_data }
      end

      def read
        set_essay_assignment
        essay_assignment_data = @essay_assignment.as_json
        essay_assignment_data[:graph_image_url] = @essay_assignment.graph_image_url if @essay_assignment.graph_image_url.present?
        render json: { success: true, essay_assignment: essay_assignment_data }
      end

      def show
        @essay_assignment = EssayAssignment.find(params[:id])
        
        # 優化：手動構建 essay_assignment 數據，避免 as_json 的開銷
        essay_assignment_data = {
          id: @essay_assignment.id,
          topic: @essay_assignment.topic,
          assignment: @essay_assignment.assignment,
          title: @essay_assignment.title,
          hints: @essay_assignment.hints,
          category: @essay_assignment.category,
          essay_type: @essay_assignment.essay_type,
          answer_visible: @essay_assignment.answer_visible,
          remark: @essay_assignment.remark,
          code: @essay_assignment.code,
          rubric: @essay_assignment.rubric,
          meta: @essay_assignment.meta,
          number_of_submission: @essay_assignment.number_of_submission,
          created_at: @essay_assignment.created_at,
          updated_at: @essay_assignment.updated_at
        }
        essay_assignment_data[:graph_image_url] = @essay_assignment.graph_image_url if @essay_assignment.graph_image_url.present?

        # 優化：移除 select，避免 schema 查詢；使用 includes 預加載關聯
        # 優化：在數據庫層面過濾，避免在 Ruby 層面處理
        @essay_gradings = @essay_assignment.essay_gradings
                                           .where.not(status: 'draft')
                                           .where.not(essay_assignment_id: nil)
                                           .includes(:general_user, :essay_assignment)
                                           .order('created_at asc')

        assignment_category = @essay_assignment.category

        essay_gradings_data = @essay_gradings.filter_map do |eg|
          EssayGradingSubmissionPayloadBuilder.call(eg, assignment_category: assignment_category)
        end

        # 優化：在 Ruby 層面排序（因為需要按 class_no 數字排序，數據庫排序可能不準確）
        essay_gradings_data.sort_by! do |eg_data|
          begin
            (eg_data[:general_user][:class_no] || '0').to_i
          rescue StandardError
            0
          end
        end

        render json: {
          success: true,
          essay_assignment: essay_assignment_data,
          essay_gradings: essay_gradings_data
        }, status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: { success: false, error: 'EssayAssignment not found' }, status: :not_found
      rescue StandardError => e
        Rails.logger.error "Error in EssayAssignmentsController#show: #{e.message}\n#{e.backtrace.first(10).join("\n")}"
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      def create
        @essay_assignment = EssayAssignment.new(essay_assignment_params)
        @essay_assignment.general_user_id = current_general_user.id
        
        # 如果指定了Community，需要验证用户权限
        if @essay_assignment.community_id.present?
          community = Community.find_by(id: @essay_assignment.community_id)
          
          unless community
            return render json: { success: false, error: 'Community not found' }, status: :not_found
          end
          
          # 检查用户是否为Community的创建者或成员
          unless community.creator?(current_general_user) || community.member?(current_general_user)
            return render json: { success: false, error: 'Access denied. You must be a member or creator of this community' }, 
                          status: :forbidden
          end
        end
        
        if @essay_assignment.save
          # 返回包含Community信息的响应
          assignment_data = @essay_assignment.as_json
          if @essay_assignment.community
            assignment_data['community'] = {
              id: @essay_assignment.community.id,
              name: @essay_assignment.community.name,
              code: @essay_assignment.community.code
            }
          end
          render json: { success: true, essay_assignment: assignment_data }, status: :created
        else
          render json: { success: false, errors: @essay_assignment.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        if @essay_assignment.update(essay_assignment_params)
          render json: { success: true, essay_assignment: @essay_assignment }, status: :ok
        else
          render json: { success: false, errors: @essay_assignment.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        @essay_assignment.destroy
        render json: { success: true, message: 'EssayAssignment deleted successfully' }, status: :ok
      end

      # 通过Community ID获取所有EssayAssignment
      def by_community
        community_id = params[:community_id]
        
        unless community_id.present?
          return render json: { success: false, error: 'Community ID is required' }, status: :bad_request
        end
        
        community = Community.find_by(id: community_id)
        unless community
          return render json: { success: false, error: 'Community not found' }, status: :not_found
        end
        
        # 检查用户权限
        unless community.creator?(current_general_user) || community.member?(current_general_user)
          return render json: { success: false, error: 'Access denied to this community' }, status: :forbidden
        end
        
        @essay_assignments = community.essay_assignments
                                      .includes(:general_user)
                                      .select(:id, :number_of_submission, :rubric, :title, :hints, :category, :answer_visible,
                                             :topic, :created_at, :updated_at, :code, :assignment, :general_user_id)
                                      .order('created_at desc')
        
        # 添加分类筛选
        if params[:category].present?
          @essay_assignments = @essay_assignments.where(category: params[:category])
        end
        
        @essay_assignments = Kaminari.paginate_array(@essay_assignments).page(params[:page])
        
        # 构建响应数据
        assignments_with_creator = @essay_assignments.map do |assignment|
          assignment_data = assignment.as_json
          assignment_data['creator'] = {
            id: assignment.general_user.id,
            nickname: assignment.general_user.nickname,
            email: assignment.general_user.email
          }
          assignment_data['community'] = {
            id: community.id,
            name: community.name,
            code: community.code
          }
          assignment_data
        end
        
        render json: { 
          success: true, 
          community: {
            id: community.id,
            name: community.name,
            code: community.code,
            description: community.description
          },
          essay_assignments: assignments_with_creator, 
          meta: pagination_meta(@essay_assignments) 
        }, status: :ok
      end

      def parse_vocab_csv
        # authorize! :create, EssayAssignment

        service = VocabCsvParserService.new(params[:file])
        result = service.parse

        if result.success?
          render json: {
            success: true,
            vocabs: result.vocabs
          }, status: :ok
        else
          render json: {
            success: false,
            error: result.error
          }, status: :unprocessable_entity
        end
      rescue StandardError => e
        render json: {
          success: false,
          error: e.message
        }, status: :internal_server_error
      end

      # 為IELTS作業生成Sample Essay
      def generate_sample_essay
        @essay_assignment = EssayAssignment.find(params[:id])

        # 檢查權限 - 只有作業創建者可以生成Sample Essay
        unless @essay_assignment.general_user_id == current_general_user.id
          render json: { success: false, error: 'Access denied' }, status: :forbidden
          return
        end

        # 檢查是否為IELTS Task 1作業
        unless @essay_assignment.name == 'IELTS Task 1'
          render json: { success: false, error: 'Sample essay generation is only available for IELTS Task 1 assignments' },
                 status: :unprocessable_entity
          return
        end

        service = SampleEssayGenerationService.new(@essay_assignment)
        result = service.call

        if result.success?
          # 將生成的Sample Essay保存到meta欄位
          @essay_assignment.update(
            meta: @essay_assignment.meta.merge('sample_essay' => result.sample_essay)
          )

          render json: {
            success: true,
            sample_essay: result.sample_essay
          }, status: :ok
        else
          render json: {
            success: false,
            error: result.error_message
          }, status: :unprocessable_entity
        end
      rescue StandardError => e
        render json: {
          success: false,
          error: "Failed to generate sample essay: #{e.message}"
        }, status: :internal_server_error
      end

      def create_essay_grading
        @essay_assignment = EssayAssignment.find_by!(code: params[:id])

        # 創建新的 essay_grading 並加載必要的關聯
        @essay_grading = @essay_assignment.essay_gradings.build(
          general_user_id: current_general_user.id,
          grading: {
            sentence_builder: params[:sentence_builder],
            app_key: @essay_assignment.rubric['app_key']['grading']
          },
          general_context: {
            app_key: @essay_assignment.rubric['app_key']['general_context']
          },
          meta: {}
        )

        # 確保加載關聯數據
        @essay_grading.general_user = current_general_user

        if @essay_grading.save
          render json: {
            success: true,
            essay_grading: @essay_grading.as_json.merge(
              general_user: @essay_grading.display_student_info
            )
          }, status: :created
        else
          render json: {
            success: false,
            errors: @essay_grading.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      private

      def set_essay_assignment
        @essay_assignment = EssayAssignment.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { success: false, error: 'EssayAssignment not found' }, status: :ok
      end

      def set_essay_assignment_by_code
        @essay_assignment = EssayAssignment.find_by!(code: params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { success: false, error: 'EssayAssignment not found' }, status: :ok
      end

      def aienglish_access
        @essay_assignment = EssayAssignment.find_by!(code: params[:id])

        # 檢查 meta 欄位中的 aienglish_features_list
        if current_general_user.aienglish_features_list.include?(@essay_assignment.category)
          true
        else
          render json: { success: false, error: 'Access denied' }, status: :ok
        end
      end

      def essay_assignment_params
        # 首先獲取基本的 permitted parameters（不包括meta，我們稍後單獨處理）
        permitted_params = params.require(:essay_assignment).permit(
          :topic,
          :assignment,
          :title,
          :hints,
          :category,
          :essay_type,
          :answer_visible,
          :remark,
          :graph_image,
          :community_id,  # 新增 community_id 支持
          rubric: [
            :name,
            { app_key: %i[grading general_context] }
          ]
        ).to_h

        # 單獨處理meta參數的不同格式
        if params[:essay_assignment][:meta].present?
          meta_param = params[:essay_assignment][:meta]

          if meta_param.is_a?(String)
            # 如果meta是JSON字符串，解析它
            begin
              parsed_meta = JSON.parse(meta_param)
              permitted_params[:meta] = parsed_meta
              Rails.logger.info('[EssayAssignmentsController] Successfully parsed meta JSON string')
            rescue JSON::ParserError => e
              Rails.logger.warn("[EssayAssignmentsController] Failed to parse meta JSON: #{e.message}")
              # 如果JSON解析失敗，保持原始字符串
              permitted_params[:meta] = meta_param
            end
          elsif meta_param.is_a?(ActionController::Parameters)
            # 如果meta是嵌套參數，允許所有鍵通過
            permitted_params[:meta] = meta_param.permit!.to_h
            Rails.logger.info('[EssayAssignmentsController] Successfully processed nested meta parameters')
          else
            # 其他情況，直接使用原值
            permitted_params[:meta] = meta_param
          end
        end

        permitted_params
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
