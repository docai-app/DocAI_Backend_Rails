# frozen_string_literal: true

require 'prawn/table'

module Api
  module V1
    class EssayGradingsController < ApiController
      before_action :authenticate_general_user!,
                    except: %i[download_reports download_report download_supplement_practice]

      def download_report
        set_essay_grading
        json_data = prepare_report_data(@essay_grading)
        pdf = generate_pdf(json_data, @essay_grading)
        send_data pdf.render, filename: "#{@essay_grading.general_user.nickname}.pdf", type: 'application/pdf',
                              disposition: 'inline'
      end

      def download_supplement_practice
        set_essay_grading

        json_data = prepare_report_data(@essay_grading)

        # 获取补充练习的文本内容
        supplement_text = @essay_grading.grading.dig('supplement_practice', 'text')
        raise 'Supplement practice text not found' unless supplement_text

        # 预处理 Markdown 文本，确保列表项正确显示
        supplement_text = supplement_text.gsub(/(\d+\.)/, "\n\\1")

        # 使用 Redcarpet 将 Markdown 转换为 HTML
        markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML,
                                           { tables: true, autolink: true, fenced_code_blocks: true, strikethrough: true, underline: true,
                                             highlight: true, quote: true, footnotes: true })
        html_content = markdown.render(supplement_text)

        # 生成 PDF
        pdf = Prawn::Document.new(page_size: 'A4', margin: 40) do |pdf|
          font_path = Rails.root.join('app/assets/fonts')

          pdf.font_families.update(
            'NotoSans' => {
              normal: font_path.join('NotoSansTC-Regular.ttf'),
              bold: font_path.join('NotoSansTC-Bold.ttf')
            },
            'DejaVuSans' => {
              normal: font_path.join('DejaVuSans.ttf'),
              bold: font_path.join('DejaVuSans.ttf'), # Fallback to normal for bold
              italic: font_path.join('DejaVuSans.ttf'), # Fallback to normal for italic
              bold_italic: font_path.join('DejaVuSans.ttf') # Fallback to normal for bold_italic
            },
            'Arial' => {
              normal: font_path.join('ARIAL.ttf'),
              bold: font_path.join('ARIALBD.ttf'),
              italic: font_path.join('ARIAL.ttf'), # Fallback to normal for italic
              bold_italic: font_path.join('ARIALBD.ttf') # Fallback to bold for bold_italic
            }
          )

          pdf.font('Arial')
          pdf.fallback_fonts(%w[NotoSans DejaVuSans])
          pdf.fill_color '000000'

          # school_logo_url = @essay_grading.
          user = @essay_grading.general_user
          school_logo_url = user.aienglish_user? ? user.school_logo_url(:small) : nil

          # 處理學校 Logo
          if school_logo_url.present?
            begin
              require 'open-uri'
              logo_tempfile = URI.open(school_logo_url)
              # Logo 尺寸調整為 50 點
              pdf.image logo_tempfile, at: [0, pdf.cursor], width: 50
              pdf.move_down 20
            rescue StandardError => e
              Rails.logger.error("Error loading school logo: #{e.message}")
            end
          else
            pdf.move_down 20
          end

          # Title
          pdf.move_down 10
          pdf.text 'Supplementary Practice Task', size: 20, style: :bold, align: :center
          pdf.stroke_color '444444'
          # pdf.stroke_horizontal_rule
          pdf.move_down 25

          # Section Title
          pdf.text 'Assignment Information', size: 15, style: :bold
          pdf.stroke_color '444444'
          pdf.stroke_horizontal_rule
          pdf.move_down 12

          info_data = [
            ['Assignment:', json_data['topic'] || 'N/A'],
            ['Account:', json_data['account'] || 'N/A']
          ]

          info_data.each do |label, value|
            pdf.formatted_text [
              { text: label, styles: [:bold], size: 12 },
              { text: " #{value}", size: 12 }
            ]
            pdf.move_down 4
          end

          # Section Title
          pdf.move_down 12
          pdf.text 'Exercises', size: 15, style: :bold
          pdf.stroke_color '444444'
          pdf.stroke_horizontal_rule

          # 在 HTML 中添加样式以设置文字大小
          html_content = "<div style='font-size: 20px;'>#{html_content}</div>"
          # 使用 prawn-html 渲染 HTML 到 PDF
          PrawnHtml.append_html(pdf, html_content)
        end

        # 发送 PDF 文件
        send_data pdf.render, filename: "#{@essay_grading.general_user.nickname}_supplement_practice.pdf",
                              type: 'application/pdf', disposition: 'inline'
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

        # 应用过滤条件
        # 1. Assignment Name 过滤（模糊搜索，不区分大小写）
        if params[:assignment_name].present?
          @essay_gradings = @essay_gradings.where(
            'essay_assignments.assignment ILIKE ?',
            "%#{params[:assignment_name].strip}%"
          )
        end

        # 2. Status 过滤（精确匹配）
        if params[:status].present?
          # 验证 status 是否为有效值
          valid_statuses = EssayGrading.statuses.keys
          status_param = params[:status].to_s.downcase
          if valid_statuses.include?(status_param)
            @essay_gradings = @essay_gradings.where(status: status_param)
          else
            render json: {
              success: false,
              error: "Invalid status. Valid values are: #{valid_statuses.join(', ')}"
            }, status: :bad_request
            return
          end
        end

        # 3. Category 过滤（精确匹配）
        if params[:category].present?
          # 验证 category 是否为有效值
          valid_categories = EssayAssignment.categories.keys
          category_param = params[:category].to_s.downcase
          if valid_categories.include?(category_param)
            # category 是 enum，需要转换为对应的整数值
            category_value = EssayAssignment.categories[category_param]
            @essay_gradings = @essay_gradings.where('essay_assignments.category = ?', category_value)
          else
            render json: {
              success: false,
              error: "Invalid category. Valid values are: #{valid_categories.join(', ')}"
            }, status: :bad_request
            return
          end
        end

        # 排序
        @essay_gradings = @essay_gradings.order('created_at desc, updated_at desc')

        # 分页
        @essay_gradings = Kaminari.paginate_array(@essay_gradings).page(params[:page]).per(params[:count] || 10)

        # 获取 category 的字符串表示
        categories = EssayAssignment.categories.invert

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

      def test_email
        set_essay_grading
        begin
          AdminNotificationMailer.assignment_stopped_notification(@essay_grading).deliver_later
        rescue StandardError => e
          Rails.logger.error("[EssayGradingService] Failed to send admin notification email: #{e.message}")
        end
      end

      # 顯示特定的 EssayGrading
      def show
        set_essay_grading_wiht_role
        # 预加载 essay_assignment 关联
        # @essay_grading = @essay_grading.includes(:essay_assignment).find(params[:id])

        # 获取 category 的字符串表示
        EssayAssignment.categories.invert

        # binding.pry
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
          score = @essay_grading.grading.dig('comprehension', 'score'),
                  full_score = @essay_grading.grading.dig('comprehension', 'full_score')
        elsif @essay_grading.category == 'speaking_pronunciation'
          score = @essay_grading['score']
          full_score = 100
          # binding.pry
        else
          score = @essay_grading.grading['score']
          full_score = @essay_grading.grading['full_score']
        end

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
            full_score:,
            score:,
            scores:,
            grading: @essay_grading.grading,
            general_context: @essay_grading.general_context,
            essay: @essay_grading.essay,
            meta: @essay_grading.meta,
            using_time: @essay_grading.using_time,
            file: @essay_grading.file.url,
            submission_class_name: @essay_grading.submission_class_name,
            submission_class_number: @essay_grading.submission_class_number,
            # transformed_newsfeed: @essay_grading.get_transformed_newsfeed,
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
              rubric: @essay_grading.essay_assignment.rubric, # 添加完整rubric信息
              graph_image_url: @essay_grading.essay_assignment.graph_image_url, # 添加圖片URL
              created_at: @essay_grading.essay_assignment.created_at,
              updated_at: @essay_grading.essay_assignment.updated_at
            }.tap do |assignment_data|
              # 記錄IELTS Task 1功能的使用情況
              if @essay_grading.essay_assignment.rubric&.dig('name') == 'IELTS Task 1'
                Rails.logger.info "[EssayGradings#show] IELTS Task 1 assignment viewed: #{@essay_grading.essay_assignment.id}"

                if assignment_data[:graph_image_url]
                  Rails.logger.info '[EssayGradings#show] Graph image available for IELTS assignment'
                else
                  Rails.logger.info '[EssayGradings#show] No graph image for IELTS assignment'
                end

                if assignment_data[:meta]&.dig('sample_essay')
                  Rails.logger.info '[EssayGradings#show] Sample essay available for IELTS assignment'
                end
              end
            end
          }
        }, status: :ok
      end

      def create
        set_essay_assignment_by_code

        # puts "set_essay_assignment_by_code: #{@essay_assignment.inspect}"

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
          # Track assignment submission（非 draft 才記錄正式提交）
          # unless @essay_grading.status == 'draft'
          #   # 首先，確保 Ahoy tracker 與當前提交作業的用戶正確關聯
          #   ahoy.authenticate(current_general_user) if current_general_user
          #   ahoy.track 'Assignment Submitted',
          #              { essay_grading_id: @essay_grading.id, essay_assignment_id: @essay_assignment.id }
          # end
          render json: { success: true, essay_grading: @essay_grading }, status: :created
        else
          render json: { success: false, errors: @essay_grading.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # 批量上传PDF文件并创建作业评分
      # POST /api/v1/essay_assignments/:essay_assignment_id/essay_gradings/batch_upload_pdfs
      def batch_upload_pdfs
        # set_essay_assignment_by_code
        essay_assignment = EssayAssignment.find(params[:essay_assignment_id])
        
        # 检查权限：只有教师或管理员可以批量上传
        unless current_general_user.aienglish_user? && 
               (current_general_user.aienglish_role == 'teacher' || current_general_user.aienglish_role == 'admin')
          render json: { success: false, error: 'Only teachers and admins can batch upload PDFs' }, status: :forbidden
          return
        end

        # 验证PDF文件参数
        pdf_files = params[:pdf_files]
        if pdf_files.blank?
          render json: { success: false, error: 'No PDF files provided' }, status: :bad_request
          return
        end

        # 验证文件类型和大小
        pdf_files.each do |file|
          unless file.content_type == 'application/pdf'
            render json: { success: false, error: "File #{file.original_filename} is not a PDF" }, status: :bad_request
            return
          end
          
          # 检查文件大小（建议不超过10MB）
          if file.size > 10.megabytes
            render json: { success: false, error: "File #{file.original_filename} is too large (max 10MB)" }, status: :bad_request
            return
          end
        end

        # 调用服务处理批量上传
        service = BatchPdfEssayService.new(essay_assignment.id, current_general_user.id)
        result = service.process_pdfs(pdf_files)

        if result.success?
          render json: {
            success: true,
            message: "Successfully processed #{result.processed_count} PDF files",
            processed_count: result.processed_count,
            successful_gradings: result.successful_gradings.map do |grading|
              {
                id: grading.id,
                student_email: grading.general_user.email,
                student_name: grading.general_user.nickname,
                status: grading.status,
                created_at: grading.created_at
              }
            end,
            not_found_emails: result.not_found_emails
          }, status: :created
        else
          render json: {
            success: false,
            error: "Failed to process some PDF files",
            processed_count: result.processed_count,
            errors: result.errors,
            successful_gradings: result.successful_gradings.map do |grading|
              {
                id: grading.id,
                student_email: grading.general_user.email,
                student_name: grading.general_user.nickname,
                status: grading.status,
                created_at: grading.created_at
              }
            end,
            not_found_emails: result.not_found_emails
          }, status: :unprocessable_entity
        end

      rescue StandardError => e
        Rails.logger.error("[EssayGradingsController#batch_upload_pdfs] Error: #{e.message}\n#{e.backtrace.join("\n")}")
        render json: { success: false, error: "Internal server error: #{e.message}" }, status: :internal_server_error
      end

      # 批量创建作业评分（JSON）
      # 支持两种请求体：
      # 1) 顶层数组：[{ nickname, meta: { files: [...] }, essay: "..." }, ...]
      # 2) 包在 gradings 键：{ gradings: [ ...同上... ] }
      # POST /api/v1/essay_assignments/:essay_assignment_id/essay_gradings/batch_create
      def batch_create
        essay_assignment = EssayAssignment.find_by(id: params[:essay_assignment_id]) ||
                           EssayAssignment.find_by(code: params[:essay_assignment_id])

        unless essay_assignment
          render json: { success: false, error: 'EssayAssignment not found' }, status: :not_found
          return
        end

        # unless current_general_user.aienglish_user? &&
        #        %w[teacher admin].include?(current_general_user.aienglish_role)
        #   render json: { success: false, error: 'Only teachers and admins can batch create' }, status: :forbidden
        #   return
        # end

        items = params[:gradings] || params[:_json]
        unless items.is_a?(Array) && items.present?
          render json: { success: false, error: 'Invalid payload: expect an array' }, status: :bad_request
          return
        end

        successful_gradings = []
        invalid_items = []
        not_found_nicknames = []
        processed_count = 0

        items.each do |item|
          nickname = item[:nickname] || item['nickname']
          if nickname.blank?
            invalid_items << { nickname: nil, errors: ['Missing nickname'] }
            next
          end

          student = GeneralUser.find_by(nickname: nickname) ||
                    GeneralUser.where('LOWER(nickname) = ?', nickname.to_s.downcase).first
          unless student
            not_found_nicknames << nickname
            next
          end

          grading_attrs = { essay: item[:essay] || item['essay'] }
          meta_input = item[:meta] || item['meta']
        #   puts "meta_input #{meta_input}"
          if meta_input.present?
            meta_hash =
              if defined?(ActionController::Parameters) && meta_input.is_a?(ActionController::Parameters)
                meta_input.to_unsafe_h
              else
                meta_input
              end
            allowed_meta_keys = %w[newsfeed_id sample_essay audiobase64s files]
            grading_attrs[:meta] = (grading_attrs[:meta] || {}).merge(meta_hash.slice(*allowed_meta_keys))
          end

          grading = essay_assignment.essay_gradings.new(grading_attrs)
          grading.general_user = student
          grading.topic = essay_assignment.topic

          if essay_assignment.rubric.present? && essay_assignment.rubric['app_key'].present?
            grading.grading ||= {}
            grading.grading['app_key'] = essay_assignment.rubric['app_key']['grading']
            grading.general_context ||= {}
            grading.general_context['app_key'] = essay_assignment.rubric['app_key']['general_context']
          end

          if grading.save
            successful_gradings << grading
            processed_count += 1
          else
            invalid_items << { nickname: nickname, errors: grading.errors.full_messages }
          end
        end

        if invalid_items.empty? && not_found_nicknames.empty?
          render json: {
            success: true,
            message: "Successfully created #{processed_count} gradings",
            processed_count: processed_count,
            successful_gradings: successful_gradings.map { |g|
              { id: g.id, student_nickname: g.general_user.nickname, status: g.status, created_at: g.created_at }
            }
          }, status: :created
        else
          render json: {
            success: false,
            error: 'Some items failed',
            processed_count: processed_count,
            successful_gradings: successful_gradings.map { |g|
              { id: g.id, student_nickname: g.general_user.nickname, status: g.status, created_at: g.created_at }
            },
            not_found_nicknames: not_found_nicknames,
            invalid_items: invalid_items
          }, status: :unprocessable_entity
        end
      rescue StandardError => e
        Rails.logger.error("[EssayGradingsController#batch_create] Error: #{e.message}\n#{e.backtrace.join("\n")}")
        render json: { success: false, error: "Internal server error: #{e.message}" }, status: :internal_server_error
      end

      # 編輯 / 更新單一 EssayGrading（包括切換 draft / 提交）
      def update
        set_essay_grading_wiht_role

        if @essay_grading.update(essay_grading_params)
          render json: { success: true, essay_grading: @essay_grading }, status: :ok
        else
          render json: { success: false, errors: @essay_grading.errors.full_messages },
                 status: :unprocessable_entity
        end
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      def download_reports
        essay_assignment = EssayAssignment.find(params[:id])
        essay_gradings = essay_assignment.essay_gradings.where(status: 'graded').includes(:general_user)

        zip_data = Zip::OutputStream.write_buffer do |zip|
          essay_gradings.each_with_index do |grading, index|
            puts "Generating report for grading: #{grading.id}, #{index}"
            report = generate_report(grading)
            # 使用 index 确保文件名唯一
            zip.put_next_entry("report_#{grading.general_user.nickname}_#{index + 1}.pdf")
            zip.write(report)
          end
        end

        send_data zip_data.string, type: 'application/zip',
                                   filename: "essay_assignment_#{essay_assignment.id}_reports.zip"
      end

      private

      # 設置特定的 EssayGrading
      def set_essay_grading
        @essay_grading = EssayGrading.find(params[:id])
      end

      def set_essay_grading_wiht_role
        if current_general_user.aienglish_role == 'teacher'
          @essay_grading = EssayGrading.find(params[:id])
        else
          @essay_grading = current_general_user.essay_gradings.find(params[:id])
        end
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
          :status, # 允許前端控制 draft / pending 等狀態
          grading: [
            :app_key,
            {
              comprehension: [
                questions: [
                  :question,
                  :answer,
                  :user_answer,
                  :indicator,
                  { options: {} }
                ]
              ]
            },
            {
              speaking_pronunciation_sentences: [
                :sentence,
                :speaking_times,
                :ipa_transcript,
                :score,
                :transcript_translation,
                { real_transcript: [] }, # 假設 real_transcript 是陣列中的純量
                { result: %i[
                  audiobase64
                  real_transcript
                  ipa_transcript
                  pronunciation_accuracy
                  real_transcripts
                  matched_transcripts
                  real_transcripts_ipa
                  matched_transcripts_ipa
                  pair_accuracy_category
                  start_time
                  end_time
                  is_letter_correct_all_words
                ] }
              ]
            }
          ],
          meta: %i[newsfeed_id sample_essay audiobase64s files],
          sentence_builder: %i[vocab sentence]
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

      def generate_comprehension_pdf(json_data, essay_grading, school_logo_url = nil, _submission_info = nil)
        Prawn::Document.new(page_size: 'A4', margin: 40) do |pdf|
          font_path = Rails.root.join('app/assets/fonts')

          pdf.font_families.update(
            'NotoSans' => {
              normal: font_path.join('NotoSansTC-Regular.ttf'),
              bold: font_path.join('NotoSansTC-Bold.ttf')
            },
            'DejaVuSans' => {
              normal: font_path.join('DejaVuSans.ttf'),
              bold: font_path.join('DejaVuSans.ttf'), # Fallback to normal for bold
              italic: font_path.join('DejaVuSans.ttf'), # Fallback to normal for italic
              bold_italic: font_path.join('DejaVuSans.ttf') # Fallback to normal for bold_italic
            },
            'Arial' => {
              normal: font_path.join('ARIAL.ttf'),
              bold: font_path.join('ARIALBD.ttf'),
              italic: font_path.join('ARIAL.ttf'), # Fallback to normal for italic
              bold_italic: font_path.join('ARIALBD.ttf') # Fallback to bold for bold_italic
            }
          )

          pdf.font('Arial')
          pdf.fallback_fonts(%w[NotoSans DejaVuSans])
          pdf.fill_color '000000'

          # 如果有學校 logo，在左上角添加 logo（在報告標題之前）
          if school_logo_url.present?
            # 下載 logo 到臨時文件
            begin
              require 'open-uri'
              logo_tempfile = URI.open(school_logo_url)
              # 在左上角顯示 logo，寬度為 50 點
              pdf.image logo_tempfile, at: [0, pdf.cursor], width: 50
              # 向下移動一定距離，以便文本不會與 logo 重疊
              pdf.move_down 20
            rescue StandardError => e
              # 如果獲取 logo 失敗，記錄錯誤但繼續生成 PDF
              Rails.logger.error("Error loading school logo: #{e.message}")
              # 不需要移動光標，因為沒有添加 logo
            end
          else
            # 沒有 logo 時正常開始內容
            pdf.move_down 20
          end

          # 开始内容部分
          # pdf.move_down 10
          pdf.text "Assessment Report (#{essay_grading.category.humanize})", size: 20, style: :bold, align: :center
          pdf.stroke_color '444444'
          pdf.move_down 25

          # Section Title
          pdf.text 'Assignment Information', size: 15, style: :bold
          pdf.stroke_color '444444'
          pdf.stroke_horizontal_rule
          pdf.move_down 12

          info_data = [
            ['Assignment:', json_data['assignment'] || 'N/A'],
            ['Topic:', json_data['topic'] || 'N/A'],
            ['Account:', essay_grading.general_user.show_in_report_name || 'N/A']
            # ['Class / Group:', essay_grading.general_user.banbie || 'N/A'],
            # ['Teacher:', submission_info || 'N/A'],
            # ['Date:', Time.zone.today.strftime('%B %d, %Y')],
            # ['Required Score:', "#{essay_grading.essay_assignment.speaking_pronunciation_pass_score || 60}%"]
          ]

          info_data.each do |label, value|
            pdf.formatted_text [
              { text: label, styles: [:bold], size: 12 },
              { text: " #{value}", size: 12 }
            ]
            pdf.move_down 4
          end
          pdf.move_down 25

          # binding.pry
          comprehension = json_data['comprehension']

          # Overview
          pdf.text 'Assessment Overview', size: 15, style: :bold
          pdf.stroke_horizontal_rule
          pdf.move_down 12

          # # 在页面底部显示分数
          # pdf.text "Overall Score: #{comprehension['score']} / #{comprehension['full_score']}", size: 14, style: :bold,
          #                                                                                       align: :center
          # pdf.move_down 10
          # pdf.stroke_horizontal_rule
          # pdf.move_down 20
          # binding.pry

          # 文章内容
          pdf.text json_data['article'].gsub("\n", '<br><br>'), size: 12, leading: 4, inline_format: true
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
            pdf.fill_color '000000' # 重置颜色为黑色
            pdf.text "My Answer: #{question['user_answer']}", style: :bold, size: 12 # 添加我的答案
            pdf.fill_color '008000'  # 设置文本颜色为绿色
            pdf.text "Correct Answer: #{question['answer']}", style: :bold, size: 12
            pdf.fill_color '000000'  # 重置颜色为黑色
            pdf.move_down 15
          end

          # Final Result
          pdf.text 'Final Result', size: 15, style: :bold
          pdf.stroke_horizontal_rule
          pdf.move_down 10
          pdf.formatted_text [
            { text: 'Overall Score: ', styles: [:bold], size: 12 },
            { text: "#{comprehension['score']} / #{comprehension['full_score']}", size: 12 }
          ]
          pdf.move_down 30

          # 页脚页码
          # pdf.number_pages '<page> of <total>', at: [pdf.bounds.right - 50, 0], align: :right, size: 12
        end
      end

      def generate_sentence_builder_pdf(json_data, essay_grading, school_logo_url = nil, _submission_info = nil)
        Prawn::Document.new(page_size: 'A4', margin: 40) do |pdf|
          font_path = Rails.root.join('app/assets/fonts')

          pdf.font_families.update(
            'NotoSans' => {
              normal: font_path.join('NotoSansTC-Regular.ttf'),
              bold: font_path.join('NotoSansTC-Bold.ttf')
            },
            'DejaVuSans' => {
              normal: font_path.join('DejaVuSans.ttf'),
              bold: font_path.join('DejaVuSans.ttf'), # Fallback to normal for bold
              italic: font_path.join('DejaVuSans.ttf'), # Fallback to normal for italic
              bold_italic: font_path.join('DejaVuSans.ttf') # Fallback to normal for bold_italic
            },
            'Arial' => {
              normal: font_path.join('ARIAL.ttf'),
              bold: font_path.join('ARIALBD.ttf'),
              italic: font_path.join('ARIAL.ttf'), # Fallback to normal for italic
              bold_italic: font_path.join('ARIALBD.ttf') # Fallback to bold for bold_italic
            }
          )

          pdf.font('Arial')
          pdf.fallback_fonts(%w[NotoSans DejaVuSans])
          pdf.fill_color '000000'

          # 如果有學校 logo，在左上角添加 logo（在報告標題之前）
          if school_logo_url.present?
            # 下載 logo 到臨時文件
            begin
              require 'open-uri'
              logo_tempfile = URI.open(school_logo_url)
              # 在左上角顯示 logo，寬度為 50 點
              pdf.image logo_tempfile, at: [0, pdf.cursor], width: 50
              # 向下移動一定距離，以便文本不會與 logo 重疊
              pdf.move_down 20
            rescue StandardError => e
              # 如果獲取 logo 失敗，記錄錯誤但繼續生成 PDF
              Rails.logger.error("Error loading school logo: #{e.message}")
              # 不需要移動光標，因為沒有添加 logo
            end
          else
            # 沒有 logo 時正常開始內容
            pdf.move_down 20
          end

          # 开始内容部分
          # pdf.move_down 20
          pdf.text "Assessment Report (#{essay_grading.category.humanize})", size: 20, style: :bold, align: :center
          pdf.stroke_color '444444'
          pdf.move_down 25

          # Section Title
          pdf.text 'Assignment Information', size: 15, style: :bold
          pdf.stroke_color '444444'
          pdf.stroke_horizontal_rule
          pdf.move_down 12

          info_data = [
            ['Assignment:', json_data['assignment'] || 'N/A'],
            ['Topic:', json_data['topic'] || 'N/A'],
            ['Account:', essay_grading.general_user.show_in_report_name || 'N/A']
            # ['Class / Group:', essay_grading.general_user.banbie || 'N/A'],
            # ['Teacher:', submission_info || 'N/A'],
            # ['Date:', Time.zone.today.strftime('%B %d, %Y')],
            # ['Required Score:', "#{essay_grading.essay_assignment.speaking_pronunciation_pass_score || 60}%"]
          ]

          info_data.each do |label, value|
            pdf.formatted_text [
              { text: label, styles: [:bold], size: 12 },
              { text: " #{value}", size: 12 }
            ]
            pdf.move_down 4
          end
          pdf.move_down 25

          # Overview
          pdf.text 'Assessment Overview', size: 15, style: :bold
          pdf.stroke_horizontal_rule
          pdf.move_down 12

          # 解析批改結果
          response = JSON.parse(essay_grading.grading['data']['text'])
          # 遍歷每個句子結果
          response['results'].each_with_index do |result, index|
            # 檢查是否有錯誤
            has_errors = result['errors'].any? { |error| error['error1'] != 'Correct' }

            # 使用 ❌ / ✅ 表示正確或錯誤
            status_symbol = has_errors ? "<color rgb='FF0000'>✘</color>" : "<color rgb='008000'>✔</color>"

            # binding.pry
            # 顯示 vocab 和狀態符號
            # vocab = essay_grading.sentence_builder[index]['vocab'] || "N/A"
            vocabs = essay_grading.essay_assignment.vocabs
            vocab = "#{vocabs[index]['word']}(#{vocabs[index]['pos']})"
            # binding.pry
            pdf.text "#{index + 1}. #{vocab} #{status_symbol}", size: 16, style: :bold, inline_format: true
            pdf.move_down 5

            # 顯示原句
            pdf.text "Original Sentence: #{result['original_sentence']}", size: 12, inline_format: true
            pdf.move_down 10

            # 如果有錯誤，才顯示修正句和錯誤信息
            if has_errors
              corrected_sentence = result['corrected_sentence']
              pdf.text "Corrected Sentence: #{corrected_sentence}", size: 12, inline_format: true
              pdf.move_down 10

              # 列出錯誤資訊
              pdf.text 'Errors:', size: 14, style: :bold
              pdf.move_down 5

              result['errors'].each_with_index do |error, _error_index|
                next if error['error1'] == 'Correct'

                # 顯示錯誤信息
                if error['word'] && error['corr']
                  pdf.text "• Mistake: #{error['corr']} (#{error['category']})", size: 12, style: :bold
                else
                  pdf.text "• (#{error['category']}) #{error['error1']}", size: 12, style: :bold
                end

                # 顯示解釋
                pdf.indent(20) do
                  pdf.text error['explanation'], size: 12 if error['explanation']
                end
                pdf.move_down 10
              end
            end

            pdf.move_down 20
          end

          # Final Result
          pdf.text 'Final Result', size: 15, style: :bold
          pdf.stroke_horizontal_rule
          pdf.move_down 10
          pdf.formatted_text [
            { text: 'Overall Score: ', styles: [:bold], size: 12 },
            { text: "#{essay_grading['grading']['score']} / #{essay_grading['grading']['full_score']}", size: 12 }
          ]
          pdf.move_down 30

          # # 頁腳頁碼
          # pdf.number_pages '<page> of <total>',
          #                  at: [pdf.bounds.right - 50, 0],
          #                  align: :right,
          #                  size: 12
        end
      end

      # def generate_speaking_conversation_pdf(json_data, essay_grading, school_logo_url = nil, submission_info = nil)

      def generate_essay_pdf(json_data, essay_grading, school_logo_url = nil, _submission_info = nil)
        Prawn::Document.new(page_size: 'A4', margin: 40) do |pdf|
          font_path = Rails.root.join('app/assets/fonts')

          pdf.font_families.update(
            'NotoSans' => {
              normal: font_path.join('NotoSansTC-Regular.ttf'),
              bold: font_path.join('NotoSansTC-Bold.ttf')
            },
            'DejaVuSans' => {
              normal: font_path.join('DejaVuSans.ttf'),
              bold: font_path.join('DejaVuSans.ttf'), # Fallback to normal for bold
              italic: font_path.join('DejaVuSans.ttf'), # Fallback to normal for italic
              bold_italic: font_path.join('DejaVuSans.ttf') # Fallback to normal for bold_italic
            },
            'Arial' => {
              normal: font_path.join('ARIAL.ttf'),
              bold: font_path.join('ARIALBD.ttf'),
              italic: font_path.join('ARIAL.ttf'), # Fallback to normal for italic
              bold_italic: font_path.join('ARIALBD.ttf') # Fallback to bold for bold_italic
            }
          )

          pdf.font('Arial')
          pdf.fallback_fonts(%w[NotoSans DejaVuSans])
          pdf.fill_color '000000'

          # 如果有學校 logo，在左上角添加 logo（在報告標題之前）
          if school_logo_url.present?
            # 下載 logo 到臨時文件
            begin
              require 'open-uri'
              logo_tempfile = URI.open(school_logo_url)
              # 在左上角顯示 logo，寬度為 50 點
              pdf.image logo_tempfile, at: [0, pdf.cursor], width: 50
              # 向下移動一定距離，以便文本不會與 logo 重疊
              pdf.move_down 20
            rescue StandardError => e
              # 如果獲取 logo 失敗，記錄錯誤但繼續生成 PDF
              Rails.logger.error("Error loading school logo: #{e.message}")
              # 不需要移動光標，因為沒有添加 logo
            end
          else
            # 沒有 logo 時正常開始內容
            pdf.move_down 20
          end

          # 开始内容部分
          pdf.text "Assessment Report (#{essay_grading.essay_assignment.category.humanize})", size: 20, style: :bold,
                                                                                              align: :center
          pdf.stroke_color '444444'
          pdf.move_down 25

          # Section Title
          pdf.text 'Assignment Information', size: 15, style: :bold
          pdf.stroke_color '444444'
          pdf.stroke_horizontal_rule
          pdf.move_down 12

          info_data = [
            ['Assignment:', json_data['assignment'] || 'N/A'],
            ['Topic:', json_data['topic'] || 'N/A'],
            ['Account:', essay_grading.general_user.show_in_report_name || 'N/A']
            # ['Class / Group:', essay_grading.general_user.banbie || 'N/A'],
            # ['Teacher:', submission_info || 'N/A'],
            # ['Date:', Time.zone.today.strftime('%B %d, %Y')],
            # ['Required Score:', "#{essay_grading.essay_assignment.speaking_pronunciation_pass_score || 60}%"]
          ]

          info_data.each do |label, value|
            pdf.formatted_text [
              { text: label, styles: [:bold], size: 12 },
              { text: " #{value}", size: 12 }
            ]
            pdf.move_down 4
          end
          pdf.move_down 15

          # 如果有graph_image_url， 
          if essay_grading.essay_assignment.graph_image_url.present?
            # 下載 logo 到臨時文件
            begin
                pdf.text 'Reference Chart/Graph:', size: 15, style: :bold
                pdf.stroke_color '444444'
                pdf.stroke_horizontal_rule
                pdf.move_down 4
                require 'open-uri'
                logo_tempfile = URI.open(essay_grading.essay_assignment.graph_image_url)
                # 在左上角顯示 logo，寬度為 50 點
                image_info = pdf.image logo_tempfile, at: [0, pdf.cursor], width: pdf.bounds.width
                # 向下移動一定距離，以便文本不會與 logo 重疊
                pdf.move_down image_info.height
            rescue StandardError => e
                # 如果獲取 logo 失敗，記錄錯誤但繼續生成 PDF
                Rails.logger.error("Error loading school logo: #{e.message}")
                # 不需要移動光標，因為沒有添加 logo
            end
        end
        pdf.move_down 10

          # 解析 JSON 数据
          sentences = JSON.parse(json_data['data']['text'])
          # # 分數
          # pdf.text "Score: #{sentences['Overall Score']} / #{sentences['Full Score']}", size: 14
          # pdf.move_down 30

          # Overview
          pdf.text 'Assessment Overview', size: 15, style: :bold
          pdf.stroke_horizontal_rule
          pdf.move_down 12

          # 添加 Part I 标题
          pdf.text 'Part I: Grammar', size: 18, style: :bold, align: :left
          pdf.move_down 20

          # 缩进 sentences 部分
          pdf.indent(20) do
            sentences.each do |key, value|
              next unless key.start_with?('Sentence') || key.start_with?('sentence')

              # 句子标题
              pdf.text "#{key}:", size: 14, style: :bold, color: '003366'
              pdf.move_down 5

              # 句子内容（带错误单词高亮）
              sentence_text = value['sentence']
              errors = value['errors']

              formatted_text = sentence_text

              # 标准化 errors 格式
              normalized_errors = {}

              # 检查 errors 的格式并进行标准化处理
              if errors.is_a?(Hash) && !errors.empty?
                normalized_errors = if errors.keys.first.to_s.start_with?('error')
                                      # 正常格式: {"error1" => {...}, "error2" => {...}}
                                      errors
                                    else
                                      # 非标准格式: {"word" => ..., "corr" => ..., ...}
                                      # 将其转换为标准格式
                                      { 'error1' => errors }
                                    end
              end

              normalized_errors.each_value do |error_value|
                error_word = error_value['word']
                formatted_text.gsub!(/\b#{Regexp.escape(error_word)}\b/) do |match|
                  "<color rgb='FF0000'>#{match}</color>"
                end
              end

              pdf.text formatted_text, size: 12, inline_format: true
              pdf.move_down 10

              if normalized_errors.any?
                pdf.indent(20) do
                  normalized_errors.each_value do |error_value|
                    category = error_value['category']
                    error_word = error_value['word']
                    explanation = error_value['explanation']
                    correction = error_value['corr']

                    # 从 corr 中提取正确的词
                    correct_word = nil
                    if correction.present? && correction.include?('->')
                      # 尝试从 "modernised -> modern" 格式中提取
                      correct_word = correction.split('->').last.strip
                    end

                    # 显示新格式的错误信息
                    category_display = convert_category(essay_grading.essay_assignment.category, category)
                    if correct_word.present?
                      pdf.text "<b>Mistake: #{error_word} -> #{correct_word} <color rgb='0000FF'>(#{category_display})</color></b>",
                               size: 11, inline_format: true
                    else
                      pdf.text "<b>Mistake: #{error_word} <color rgb='0000FF'>(#{category_display})</color></b>",
                               size: 11, inline_format: true
                    end

                    # 显示解释
                    pdf.text explanation, size: 10
                    pdf.move_down 8

                    # pdf.text "• #{error_word}<color rgb='0000FF'>(#{convert_category(essay_grading.essay_assignment.category, category)})</color>: #{explanation}",
                    #          size: 10, inline_format: true
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
          if json_data['general_context'].present?
            pdf.text (json_data['general_context']).to_s, size: 12, leading: 5
          else
            pdf.text (sentences['Overall coherence']).to_s, size: 12, leading: 5
          end
          if json_data['overall_comment'].present?
            pdf.text 'Overall Comment:', size: 14, style: :bold, color: '003366'
            pdf.text (json_data['overall_comment']).to_s, size: 12, leading: 5
            pdf.move_down 20
          end
          if json_data['detailedFeedback'].present?
            pdf.text 'Detailed Feedback and Suggestions:', size: 14, style: :bold, color: '003366'
            pdf.text (json_data['detailedFeedback']).to_s, size: 12, leading: 5
          end
          pdf.move_down 20

          if params[:role] == 'teacher' && essay_grading.essay_assignment.category == 'essay'
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

          # Final Result
          # pdf.text 'Final Result', size: 15, style: :bold
          # pdf.stroke_horizontal_rule
          # pdf.move_down 10
          # pdf.formatted_text [
          #   { text: 'Overall Score: ', styles: [:bold], size: 12 },
          #   { text: (sentences['Overall Score']).to_s, size: 12 }
          # ]
          # pdf.move_down 30
        end
      end

      def generate_speaking_pronunciation_pdf(json_data, essay_grading, school_logo_url = nil, _submission_info = nil)
        Prawn::Document.new(page_size: 'A4', margin: 40) do |pdf|
          font_path = Rails.root.join('app/assets/fonts')

          pdf.font_families.update(
            'NotoSans' => {
              normal: font_path.join('NotoSansTC-Regular.ttf'),
              bold: font_path.join('NotoSansTC-Bold.ttf')
            },
            'DejaVuSans' => {
              normal: font_path.join('DejaVuSans.ttf'),
              bold: font_path.join('DejaVuSans.ttf'), # Fallback to normal for bold
              italic: font_path.join('DejaVuSans.ttf'), # Fallback to normal for italic
              bold_italic: font_path.join('DejaVuSans.ttf') # Fallback to normal for bold_italic
            },
            'Arial' => {
              normal: font_path.join('ARIAL.ttf'),
              bold: font_path.join('ARIALBD.ttf'),
              italic: font_path.join('ARIAL.ttf'), # Fallback to normal for italic
              bold_italic: font_path.join('ARIALBD.ttf') # Fallback to bold for bold_italic
            }
          )

          pdf.font('Arial')
          pdf.fallback_fonts(%w[NotoSans DejaVuSans])
          pdf.fill_color '000000'

          # 處理學校 Logo
          if school_logo_url.present?
            begin
              require 'open-uri'
              logo_tempfile = URI.open(school_logo_url)
              # Logo 尺寸調整為 50 點
              pdf.image logo_tempfile, at: [0, pdf.cursor], width: 50
              pdf.move_down 20
            rescue StandardError => e
              Rails.logger.error("Error loading school logo: #{e.message}")
            end
          else
            pdf.move_down 20
          end

          # Title
          # pdf.move_down 10
          pdf.text 'Assessment Report (Pronunciation)', size: 20, style: :bold, align: :center
          pdf.stroke_color '444444'
          # pdf.stroke_horizontal_rule
          pdf.move_down 25

          # Section Title
          pdf.text 'Assignment Information', size: 15, style: :bold
          pdf.stroke_color '444444'
          pdf.stroke_horizontal_rule
          pdf.move_down 12

          info_data = [
            ['Assignment:', json_data['assignment'] || 'N/A'],
            ['Account:', essay_grading.general_user.show_in_report_name || 'N/A'],
            # ['Class / Group:', essay_grading.general_user.banbie || 'N/A'],
            # ['Teacher:', submission_info || 'N/A'],
            # ['Date:', Time.zone.today.strftime('%B %d, %Y')],
            ['Required Score:', "#{essay_grading.essay_assignment.speaking_pronunciation_pass_score || 60}%"]
          ]

          info_data.each do |label, value|
            pdf.formatted_text [
              { text: label, styles: [:bold], size: 12 },
              { text: " #{value}", size: 12 }
            ]
            pdf.move_down 4
          end
          pdf.move_down 25

          # Overview
          pdf.text 'Assessment Overview', size: 15, style: :bold
          pdf.stroke_horizontal_rule
          pdf.move_down 12

          essay_grading.essay_assignment.speaking_pronunciation_pass_score || 60
          sentences = essay_grading.grading['speaking_pronunciation_sentences'] || []

          sentences.each_with_index do |data, idx|
            pdf.text "Question #{idx + 1}", style: :bold, size: 13
            pdf.move_down 6

            details = [
              ['Expected:', data['sentence'] || ''],
              ['Student:', data.dig('result', 'real_transcript') || ''],
              ['Expected IPA:', "/#{Array(data.dig('result', 'matched_transcripts_ipa')).join(' ')}/"],
              ['Student IPA:', "/#{Array(data.dig('result', 'real_transcripts_ipa')).join(' ')}/"],
              ['Score:', "#{data['score'].to_i}%"]
            ]

            details.each do |label, value|
              pdf.formatted_text [
                { text: label, styles: [:bold], size: 11 },
                { text: " #{value}", size: 11 }
              ]
              pdf.move_down 3
            end

            # Score bar
            score = data['score'].to_i
            bar_width = 400
            bar_height = 14
            filled_width = bar_width * score / 100.0

            pdf.move_down 6
            pdf.fill_color 'eeeeee'
            pdf.rounded_rectangle([pdf.bounds.left, pdf.cursor], bar_width, bar_height, 7)
            pdf.fill

            pdf.fill_color '333333'
            pdf.rounded_rectangle([pdf.bounds.left, pdf.cursor], filled_width, bar_height, 7)
            pdf.fill

            pdf.fill_color 'ffffff'
            pdf.draw_text "#{score}%", at: [pdf.bounds.left + 5, pdf.cursor + 2], size: 10
            pdf.fill_color '000000'

            pdf.move_down 25
            pdf.stroke_color 'aaaaaa'
            pdf.dash(1, space: 2)
            pdf.stroke_horizontal_rule
            pdf.undash
            pdf.stroke_color '000000'
            pdf.move_down 25
          end

          # Final Result
          pdf.text 'Final Result', size: 15, style: :bold
          pdf.stroke_horizontal_rule
          pdf.move_down 10
          pdf.formatted_text [
            { text: 'Overall Score: ', styles: [:bold], size: 12 },
            { text: "#{essay_grading['score'].to_i}%", size: 12 }
          ]
          pdf.move_down 30

          # Footer
          # pdf.fill_color '555555'
          # pdf.text 'This report was generated automatically from the pronunciation assessment system.', size: 10 #, style: :italic
          # pdf.fill_color '000000'

          # Page Number
          # pdf.number_pages 'Page <page> of <total>', at: [pdf.bounds.right - 100, 0], align: :right, size: 10
        end
      end

      def generate_report(grading)
        grading = EssayGrading.includes(:essay_assignment).find(grading.id) # 确保 essay_assignment 被加载
        json_data = prepare_report_data(grading)
        pdf = generate_pdf(json_data, grading)
        pdf.render
      end

      def generate_pdf(json_data, essay_grading)
        assignment = essay_grading.essay_assignment
        raise "Essay assignment not found for grading ID #{essay_grading.id}" if assignment.nil?

        # 獲取用戶
        user = essay_grading.general_user

        # 只有 AI English 用戶才會有學校 logo
        school_logo_url = user.aienglish_user? ? user.school_logo_url(:small) : nil

        # 準備用戶顯示資訊（優先使用提交班級資訊）
        submission_info = prepare_submission_info(essay_grading)

        # 根據不同類型生成不同報告
        if assignment.category == 'comprehension'
          generate_comprehension_pdf(json_data, essay_grading, school_logo_url, submission_info)
        elsif assignment.category == 'speaking_pronunciation' # 新增對 speaking_pronunciation 的專門處理
          generate_speaking_pronunciation_pdf(json_data, essay_grading, school_logo_url, submission_info)
        elsif assignment.category.include?('essay')
          generate_essay_pdf(json_data, essay_grading, school_logo_url, submission_info)
        elsif assignment.category.include?('sentence_builder')
          generate_sentence_builder_pdf(json_data, essay_grading, school_logo_url, submission_info)
        elsif assignment.category.include?('speaking_conversation')
          generate_essay_pdf(json_data, essay_grading, school_logo_url, submission_info)
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
        elsif assignment.category.include?('essay') || assignment.category == 'speaking_conversation'
          json_data.merge!(essay_grading.grading)
          if essay_grading.general_context['data'].present?

            text = essay_grading.general_context['data']['text']
            fixed_json = fix_json_newlines(text)

            general_context = JSON.parse(fixed_json)
            json_data['general_context'] = general_context['Feedback'] if general_context['Feedback'].present?

            # 2025-05-11 新增以下
            if general_context['studentFeedback'].present?
              json_data['overall_comment'] =
                general_context['studentFeedback']['overall']
            end
            if general_context['studentFeedback'].present?
              json_data['detailedFeedback'] =
                general_context['studentFeedback']['detailedFeedback']
            end
          end
        end

        json_data
      end

      # 準備提交資訊（優先使用submission的班級資訊）
      def prepare_submission_info(essay_grading)
        user = essay_grading.general_user

        # 優先使用submission信息（如果存在）
        class_name = essay_grading.submission_class_name.presence || user.banbie
        class_number = essay_grading.submission_class_number.presence || user.class_no

        "#{user.email} (#{user.nickname}, #{class_name}, #{class_number})"
      end

      def fix_json_newlines(json_str)
        # 匹配双引号包围的字符串（非贪婪，支持多行），替换内部的 \n 为 \\n
        # 注意：这不处理嵌套转义的 \"，但你的数据中似乎没有
        json_str.gsub(/"((?:[^"\\]|\\.)*)"/) do |match|
          quoted = $1  # 捕获字符串内容
          fixed_content = quoted.gsub("\n", '\\n')  # 只转义 \n
          "\"#{fixed_content}\""  # 重建字符串
        end
      end

    end
  end
end
