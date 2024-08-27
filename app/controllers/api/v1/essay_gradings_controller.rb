# frozen_string_literal: true

module Api
  module V1
    class EssayGradingsController < ApiController
      before_action :authenticate_general_user!, except: [:download_report]

      def download_report
        set_essay_grading
        assignment = @essay_grading.essay_assignment
        json_data = {}

        if assignment.category == 'comprehension'
          json_data['comprehension'] = @essay_grading.grading['comprehension']
          json_data['topic'] = assignment.topic

          newsfeed = assignment.get_news_feed
          if newsfeed.present?
            json_data['title'] = newsfeed['data']['title']
            json_data['article'] = newsfeed['data']['content']
          end
          # binding.pry
          pdf = generate_comprehension_pdf(json_data)
        elsif assignment.category.include?('essay')
          pdf = generate_essay_pdf(@essay_grading.grading)
        else
          pdf = generate_pdf_from_json(json_data)
        end

        send_data pdf.render, filename: "#{@essay_grading.general_user.nickname}.pdf", type: 'application/pdf', disposition: 'inline' # disposition: "attachment"
      end

      def index
        # 联合查询，以便选择 essay_assignment 中的 newsfeed_id 字段
        @essay_gradings = current_general_user.essay_gradings
                                              .joins(:essay_assignment)
                                              .select(
                                                'essay_gradings.id,
                                                 essay_gradings.topic,
                                                 essay_gradings.created_at,
                                                 essay_gradings.updated_at,
                                                 essay_gradings.status,
                                                 essay_gradings.using_time,
                                                 essay_assignments.category as essay_assignment_category,
                                                 essay_assignments.assignment AS assignment_name,
                                                 essay_gradings.meta ->> \'newsfeed_id\' AS newsfeed_id'
                                              )
                                              .order('created_at desc, updated_at desc')

        @essay_gradings = Kaminari.paginate_array(@essay_gradings).page(params[:page]).per(params[:count] || 10)

        # 获取 category 的字符串表示
        categories = EssayAssignment.categories.invert

        # binding.pry

        render json: {
          success: true,
          essay_gradings: @essay_gradings.map do |eg|
            {
              id: eg.id,
              topic: eg.topic,
              created_at: eg.created_at,
              updated_at: eg.updated_at,
              status: eg.status,
              assignment_name: eg.assignment_name,
              category: categories[eg['essay_assignment_category']], # 使用 categories 映射获取字符串表示
              using_time: eg.using_time,
              newsfeed_id: eg['newsfeed_id'] # 添加 newsfeed_id
            }
          end,
          meta: pagination_meta(@essay_gradings)
        }, status: :ok
      end

      # 顯示特定的 EssayGrading
      def show
        set_essay_grading
        # 预加载 essay_assignment 关联
        # @essay_grading = @essay_grading.includes(:essay_assignment).find(params[:id])

        # 获取 category 的字符串表示
        EssayAssignment.categories.invert

        render json: {
          success: true,
          essay_grading: {
            id: @essay_grading.id,
            topic: @essay_grading.topic,
            created_at: @essay_grading.created_at,
            updated_at: @essay_grading.updated_at,
            status: @essay_grading.status,
            number_of_suggestion: @essay_grading.grading['number_of_suggestion'],
            questions_count: @essay_grading.grading.dig('comprehension', 'questions_count'),
            full_score: @essay_grading.grading.dig('comprehension', 'full_score'),
            score: @essay_grading.grading.dig('comprehension', 'score'),
            grading: @essay_grading.grading,
            general_context: @essay_grading.general_context,
            essay: @essay_grading.essay,
            using_time: @essay_grading.using_time,
            general_user: {
              id: @essay_grading.general_user.id,
              nickname: @essay_grading.general_user.nickname,
              class_name: @essay_grading.general_user.banbie,
              class_no: @essay_grading.general_user.class_no
            },
            essay_assignment: {
              id: @essay_grading.essay_assignment.id,
              app_key: @essay_grading.essay_assignment.app_key,
              name: @essay_grading.essay_assignment.name,
              category: @essay_grading.essay_assignment.category,
              newsfeed_id: @essay_grading.essay_assignment.newsfeed_id,
              created_at: @essay_grading.essay_assignment.created_at,
              updated_at: @essay_grading.essay_assignment.updated_at
            }
          }
        }, status: :ok
      end

      def create
        set_essay_assignment_by_code

        puts "set_essay_assignment_by_code: #{@essay_assignment.inspect}"

        @essay_grading = @essay_assignment.essay_gradings.new(essay_grading_params)
        @essay_grading.general_user = current_general_user
        @essay_grading.topic = @essay_assignment.topic

        if @essay_assignment.rubric.present? && @essay_assignment.rubric['app_key'].present?
          @essay_grading.grading ||= {}
          @essay_grading.grading['app_key'] = @essay_assignment.rubric['app_key']['grading']
          @essay_grading.general_context ||= {}
          @essay_grading.general_context['app_key'] = @essay_assignment.rubric['app_key']['general_context']
        end

        if @essay_grading.save
          render json: { success: true, essay_grading: @essay_grading }, status: :created
        else
          render json: { success: false, errors: @essay_grading.errors.full_messages }, status: :unprocessable_entity
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

      private

      # 設置特定的 EssayGrading
      def set_essay_grading
        # @essay_grading = current_general_user.essay_gradings.find(params[:id])
        @essay_grading = EssayGrading.find(params[:id])
      end

      def set_essay_assignment_by_code
        @essay_assignment = EssayAssignment.find_by!(code: params[:essay_assignment_id])
      rescue ActiveRecord::RecordNotFound
        render json: { success: false, error: 'EssayAssignment not found' }, status: :not_found
      end

      def essay_grading_params
        params.require(:essay_grading).permit(
          :essay,
          :topic,
          :file,
          :using_time,
          grading: [
            :app_key,
            { comprehension: [
              questions: [
                :question,
                :answer,
                :user_answer,
                { options: {} }
              ]
            ] }
          ],
          meta: [:newsfeed_id]
        )
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

      def generate_pdf_from_json(json_data, pdf = nil, indent_level = 0)
        pdf ||= Prawn::Document.new

        json_data.each do |key, value|
          case value
          when Hash
            pdf.text "#{'  ' * indent_level}<b>#{key.capitalize}:</b>", inline_format: true, size: 14
            generate_pdf_from_json(value, pdf, indent_level + 1)
          when Array
            pdf.text "#{'  ' * indent_level}<b>#{key.capitalize}:</b>", inline_format: true, size: 14
            value.each_with_index do |item, index|
              pdf.text "#{'  ' * (indent_level + 1)}<b>Item #{index + 1}:</b>", inline_format: true
              generate_pdf_from_json(item, pdf, indent_level + 2)
            end
          else
            pdf.text "#{'  ' * indent_level}<b>#{key.capitalize}:</b> #{value}", inline_format: true, size: 12
          end
          pdf.move_down 10
        end

        pdf
      end

      def generate_comprehension_pdf(json_data)
        Prawn::Document.new do |pdf|
          # 加载和注册字体
          font_path = Rails.root.join('app/assets/fonts/')
          pdf.font_families.update(
            'NotoSans' => {
              normal: font_path.join('NotoSansTC-Regular.ttf'),
              bold: font_path.join('NotoSansTC-Bold.ttf')
            }
          )

          # 设置默认字体
          pdf.font 'NotoSans'

          # 标题
          pdf.text json_data['title'], size: 24, style: :bold, align: :center
          pdf.move_down 20

          # 话题
          pdf.text "Topic: #{json_data['topic']}", size: 18, style: :bold
          pdf.move_down 10

          # binding.pry

          # 文章内容
          pdf.text json_data['article'], size: 12, leading: 4
          pdf.move_down 20

          # 理解测试部分
          pdf.text 'Comprehension Questions', size: 18, style: :bold
          pdf.move_down 10

          comprehension = json_data['comprehension']
          comprehension['questions'].each_with_index do |question, index|
            pdf.text "#{index + 1}. #{question['question']}", size: 14, style: :bold
            pdf.move_down 5

            question['options'].each do |key, option|
              pdf.text "  #{key}: #{option}", size: 12
            end

            pdf.move_down 5
            pdf.fill_color '008000'  # 设置文本颜色为绿色
            pdf.text "Correct Answer: #{question['answer']}", style: :bold, size: 12
            pdf.fill_color '000000'  # 重置颜色为黑色
            pdf.move_down 15
          end

          # 在页面底部显示分数
          pdf.text "Score: #{comprehension['score']} / #{comprehension['full_score']}", size: 14, style: :bold
          pdf.move_down 10

          # 页脚页码
          pdf.number_pages '<page> of <total>', at: [pdf.bounds.right - 50, 0], align: :right, size: 12
        end
      end

      def generate_essay_pdf(json_data)
        Prawn::Document.new do |pdf|
          # 加载和注册字体
          font_path = Rails.root.join('app/assets/fonts/')
          pdf.font_families.update(
            'NotoSans' => {
              normal: font_path.join('NotoSansTC-Regular.ttf'),
              bold: font_path.join('NotoSansTC-Bold.ttf')
            }
          )

          # 设置默认字体
          pdf.font 'NotoSans'

          # 添加标题
          pdf.text 'Essay Report', size: 24, style: :bold, align: :center
          pdf.move_down 20

          # 解析 JSON 数据
          sentences = JSON.parse(json_data['data']['text'])

          # 逐句添加内容和错误说明
          sentences.each do |key, value|
            next unless key.start_with?('Sentence')

            # 打印句子
            pdf.text value['sentence'], size: 14, style: :bold
            pdf.move_down 5

            # 打印该句子的错误
            if value['errors'].any?
              value['errors'].each_value do |error_value|
                pdf.fill_color 'FF0000'  # 设置文本颜色为红色
                pdf.text "#{error_value['word']}: #{error_value['explanation']}", size: 12, indent_paragraphs: 20
                pdf.fill_color '000000'  # 重置颜色为黑色
                pdf.move_down 5
              end
            end

            pdf.move_down 10
          end

          # 添加评分标准和解释
          # pdf.text "Grading Criteria", size: 18, style: :bold
          # pdf.move_down 10

          # %w[Criterion1 Criterion2 Criterion3 Criterion4].each do |criterion|
          #   criterion_data = sentences[criterion]
          #   pdf.text "#{criterion_data.keys[0]}: #{criterion_data.values[0]} / 9", size: 14, style: :bold
          #   pdf.text criterion_data["explanation"], size: 12, indent_paragraphs: 20
          #   pdf.move_down 10
          # end

          # # 添加总评分和反馈
          # pdf.text "Overall Score: #{json_data['data']['Overall Score']} / 9", size: 16, style: :bold
          # pdf.move_down 10
          # pdf.text "Overall Coherence and Readability:", size: 14, style: :bold
          # pdf.text json_data['data']["Essay's overall coherence and readability"], size: 12, indent_paragraphs: 20
          # pdf.move_down 10

          # pdf.text "Final Feedback:", size: 14, style: :bold
          # pdf.text json_data['data']['Final Feedback'], size: 12, indent_paragraphs: 20
        end
      end
    end
  end
end
