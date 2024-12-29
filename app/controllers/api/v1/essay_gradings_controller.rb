# frozen_string_literal: true

module Api
  module V1
    class EssayGradingsController < ApiController
      before_action :authenticate_general_user!, except: [:download_report]

      def download_report
        set_essay_grading
        json_data = prepare_report_data(@essay_grading)
        pdf = generate_pdf(json_data, @essay_grading)
        send_data pdf.render, filename: "#{@essay_grading.general_user.nickname}.pdf", type: 'application/pdf', disposition: 'inline'
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
            file: @essay_grading.file.url,
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
              remark: @essay_grading.essay_assignment.remark,
              answer_visible: @essay_grading.essay_assignment.answer_visible,
              newsfeed_id: @essay_grading.essay_assignment.newsfeed_id,
              meta: @essay_grading.essay_assignment.meta,
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

      def download_reports
        essay_assignment = EssayAssignment.find(params[:id])
        essay_gradings = essay_assignment.essay_gradings.where(status: 'graded').includes(:general_user)

        zip_data = Zip::OutputStream.write_buffer do |zip|
          essay_gradings.each_with_index do |grading, index|
            report = generate_report(grading)
            # 使用 index 确保文件名唯一
            zip.put_next_entry("report_#{grading.general_user.nickname}_#{index + 1}.pdf")
            zip.write(report)
          end
        end

        send_data zip_data.string, type: 'application/zip', filename: "essay_assignment_#{essay_assignment.id}_reports.zip"
      end

      private

      # 設置特定的 EssayGrading
      def set_essay_grading
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

      def convert_category(context, category)
        # 定义 essay grading 的映射
        essay_grading_mapping = {
          'A' => 'Spelling and Grammar Errors',
          'B' => 'Punctuation and Capitalization',
          'C' => 'Word Choice and Word Usage',
          'D' => 'Sentence Structure'
        }

        # 定义 speaking_essay 和 speaking_conversation 的映射
        speaking_mapping = {
          'A' => 'Grammatical Errors',
          'B' => 'Lexical Errors',
          'C' => 'Speech Errors'
        }

        # 根据 context 选择正确的映射
        case context
        when 'essay'
          essay_grading_mapping[category]
        when 'speaking_essay', 'speaking_conversation'
          speaking_mapping[category]
        else
          'Unknown category' # 处理未知的 context 或 category
        end
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

      def generate_comprehension_pdf(json_data, essay_grading)
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

          # 开始内容部分
          pdf.move_down 20
          pdf.text "Grading Report(#{essay_grading.category})", size: 20, style: :bold, align: :center
          pdf.move_down 10

          # 话题
          if json_data['assignment'].present?
            pdf.text "Assignment: #{json_data['assignment']}", size: 14 # , style: :bold
            pdf.move_down 10
          end

          # 话题
          pdf.text "Topic: #{json_data['topic']}", size: 14 # , style: :bold
          pdf.move_down 10

          # 學生資訊
          pdf.text "Account: #{json_data['account']}", size: 14
          pdf.move_down 30

          # binding.pry
          comprehension = json_data['comprehension']

          # 在页面底部显示分数
          pdf.text "Overall Score: #{comprehension['score']} / #{comprehension['full_score']}", size: 14, style: :bold, align: :center
          pdf.move_down 10
          pdf.stroke_horizontal_rule
          pdf.move_down 20
          # binding.pry

          # 文章内容
          pdf.text json_data['article'].gsub("\n", "<br><br>"), size: 12, leading: 4, inline_format: true
          pdf.move_down 20

          # binding.pry

          pdf.stroke_horizontal_rule
          pdf.move_down 20

          # 理解测试部分
          pdf.text 'Comprehension Questions', size: 18, style: :bold
          pdf.move_down 10

          comprehension['questions'].each_with_index do |question, index|
            pdf.text "#{index + 1}. #{question['question']}", size: 14, style: :bold
            pdf.move_down 5

            question['options'].each do |key, option|
              pdf.text "  #{key}: #{option}", size: 12
            end

            pdf.move_down 5
            pdf.fill_color '000000'  # 重置颜色为黑色
            pdf.text "My Answer: #{question['user_answer']}", style: :bold, size: 12 # 添加我的答案
            pdf.fill_color '008000'  # 设置文本颜色为绿色
            pdf.text "Correct Answer: #{question['answer']}", style: :bold, size: 12
            pdf.fill_color '000000'  # 重置颜色为黑色
            pdf.move_down 15
          end

          # 页脚页码
          pdf.number_pages '<page> of <total>', at: [pdf.bounds.right - 50, 0], align: :right, size: 12
        end
      end

      def generate_essay_pdf(json_data, essay_grading)
        pdf = Prawn::Document.new(page_size: 'A4', margin: 40)

        # 设置全局样式
        font_path = Rails.root.join('app/assets/fonts/')
        pdf.font_families.update(
          'NotoSans' => {
            normal: font_path.join('NotoSansTC-Regular.ttf'),
            bold: font_path.join('NotoSansTC-Bold.ttf')
          }
        )
        pdf.font 'NotoSans'

        # 开始内容部分
        pdf.move_down 20
        pdf.text "Grading Report(#{essay_grading.essay_assignment.category})", size: 20, style: :bold, align: :center
        pdf.move_down 10

        # 话题
        if json_data['assignment'].present?
          pdf.text "Assignment: #{json_data['assignment']}", size: 14
          pdf.move_down 10
        end

        # 话题
        pdf.text "Topic: #{json_data['topic']}", size: 14
        pdf.move_down 10

        # 学生信息
        pdf.text "Account: #{json_data['account']}", size: 14
        pdf.move_down 30

        # 解析 JSON 数据
        sentences = JSON.parse(json_data['data']['text'])

        # 添加 Part I 标题
        pdf.text 'Part I: Grammar', size: 18, style: :bold, align: :left
        pdf.move_down 20

        # 缩进 sentences 部分
        pdf.indent(20) do
          sentences.each do |key, value|
            next unless key.start_with?('Sentence')

            # 句子标题
            pdf.text "#{key}:", size: 14, style: :bold, color: '003366'
            pdf.move_down 5

            # 句子内容（带错误单词高亮）
            sentence_text = value['sentence']
            errors = value['errors']

            formatted_text = sentence_text

            errors.each_value do |error_value|
              error_word = error_value['word']
              formatted_text.gsub!(/\b#{Regexp.escape(error_word)}\b/) do |match|
                "<color rgb='FF0000'>#{match}</color>"
              end
            end

            pdf.text formatted_text, size: 12, inline_format: true
            pdf.move_down 10

            if errors.any?
              pdf.indent(20) do
                errors.each_value do |error_value|
                  category = error_value['category']
                  error_word = error_value['word']
                  explanation = error_value['explanation']

                  pdf.text "• #{error_word}<color rgb='0000FF'>(#{convert_category(essay_grading.essay_assignment.category, category)})</color>: #{explanation}",
                           size: 10, inline_format: true
                  pdf.move_down 5
                end
              end
              pdf.move_down 10
            end

            pdf.move_down 15
          end
        end

        pdf.text 'Part II: General Context', size: 18, style: :bold, align: :left
        pdf.move_down 20
        pdf.text (json_data['general_context']).to_s, size: 12, leading: 5
        pdf.move_down 20

        if @role == 'teacher' && essay_grading.essay_assignment.category == 'essay'
          pdf.text 'Part III: Score', size: 18, style: :bold, align: :left
          pdf.move_down 20
          if sentences['Overall Score']
            pdf.text "Overall Score #{sentences['Overall Score']}/#{sentences['Full Score']}", size: 16, style: :bold,
                                                                                               color: '003366', align: :center

            sentences.each do |key, value|
              next unless key.start_with?('Criterion')

              value.each do |criterion_name, criterion_value|
                next if ['Full Score', 'explanation'].include?(criterion_name)

                pdf.text "#{criterion_name}:", size: 14, style: :bold, color: '003366'
                pdf.move_down 5

                full_score = value['Full Score'] || 'N/A'
                score = criterion_value

                pdf.text "Score: #{score} / #{full_score}", size: 12
                pdf.move_down 10

                if value['explanation']
                  pdf.indent(20) do
                    pdf.text value['explanation'], size: 10
                    pdf.move_down 15
                  end
                end

                pdf.stroke_horizontal_rule
                pdf.move_down 15
              end
            end
          end
        end

        pdf
      end

      def generate_report(grading)
        grading = EssayGrading.includes(:essay_assignment).find(grading.id) # 确保 essay_assignment 被加载
        json_data = prepare_report_data(grading)
        pdf = generate_pdf(json_data, grading)
        pdf.render
      end

      def generate_pdf(json_data, essay_grading)
        assignment = essay_grading.essay_assignment
        if assignment.nil?
          raise "Essay assignment not found for grading ID #{essay_grading.id}"
        end

        if assignment.category == 'comprehension'
          generate_comprehension_pdf(json_data, essay_grading)
        elsif assignment.category.include?('essay')
          generate_essay_pdf(json_data, essay_grading)
        else
          generate_pdf_from_json(json_data)
        end
      end

      def prepare_report_data(essay_grading)
        assignment = essay_grading.essay_assignment
        json_data = {
          'topic' => assignment.topic,
          'account' => essay_grading.general_user.show_in_report_name,
          'assignment' => assignment.assignment
        }

        if assignment.category == 'comprehension'
          json_data['comprehension'] = essay_grading.grading['comprehension']
          newsfeed = essay_grading.get_news_feed
          if newsfeed.present?
            json_data['title'] = newsfeed['data']['title']
            json_data['article'] = newsfeed['data']['content'] || newsfeed['data']['text']
          end
        elsif assignment.category.include?('essay')
          json_data.merge!(essay_grading.grading)
          if essay_grading.general_context['data'].present?
            general_context = JSON.parse(essay_grading.general_context['data']['text'])
            json_data['general_context'] = general_context['Feedback'] if general_context['Feedback'].present?
          end
        end

        json_data
      end
    end
  end
end
