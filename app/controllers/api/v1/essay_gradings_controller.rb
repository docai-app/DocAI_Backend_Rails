# frozen_string_literal: true

require 'open-uri'
require 'prawn/table'
require 'stringio'

module Api
  module V1
    class EssayGradingsController < ApiController
      before_action :authenticate_general_user!,
                    except: %i[download_reports download_report download_supplement_practice]

      def download_report
        set_essay_grading
        report_type = normalized_report_type
        json_data = prepare_report_data(@essay_grading, report_type)
        pdf = generate_pdf(json_data, @essay_grading, report_type)
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
        pdf = Prawn::Document.new(page_size: 'A4', margin: [40, 40, 88, 40]) do |pdf|
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
          draw_standard_report_footer(pdf)

          # school_logo_url = @essay_grading.
          user = @essay_grading.general_user
          school_logo_url = user.aienglish_user? ? user.school_logo_url(:small) : nil

          render_school_logo(pdf, school_logo_url)

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
        elsif @essay_grading.category == 'listening'
          score = @essay_grading.grading.dig('listening', 'score')
          full_score = @essay_grading.grading.dig('listening', 'full_score')
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
            questions_count: @essay_grading.grading.dig('comprehension', 'questions_count') || @essay_grading.grading.dig('listening', 'questions_count'),
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
          # 檢查是否有對應的作業分配，如果有則更新分配狀態
          # 只有非草稿狀態的提交才更新分配狀態
          update_assignment_status_if_needed unless @essay_grading.status == 'draft'

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
          # 如果狀態從 draft 變為非 draft，需要更新分配狀態
          if @essay_grading.saved_change_to_status? && 
             @essay_grading.status != 'draft' && 
             @essay_grading.status_before_last_save == 'draft'
            # 需要設置 @essay_assignment 以便 update_assignment_status_if_needed 使用
            @essay_assignment = @essay_grading.essay_assignment
            update_assignment_status_if_needed
          end

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
        report_type = normalized_report_type

        zip_data = Zip::OutputStream.write_buffer do |zip|
          essay_gradings.each_with_index do |grading, index|
            puts "Generating report for grading: #{grading.id}, #{index}"
            report = generate_report(grading, report_type)
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
                  :summary,
                  :type,
                  :chosen_paragraphs,
                  { blanks: [:id, :answer, :user_answer] },
                  { options: {} }
                ]
              ]
            },
            {
              listening: [
                :play_count,
                :listening_form_id,
                :level,
                :score,
                :full_score,
                :percentage,
                questions: [
                  :id,
                  :question,
                  :answer,
                  :user_answer,
                  :indicator,
                  :summary,
                  :type,
                  :is_correct,
                  { blanks: [:id, :answer, :user_answer] },
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
          meta: %i[newsfeed_id sample_essay audiobase64s files listening_form_id],
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
        Prawn::Document.new(page_size: 'A4', margin: [40, 40, 88, 40]) do |pdf|
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
          draw_standard_report_footer(pdf)

          render_school_logo(pdf, school_logo_url)

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
          
            if question['type'] == 'fill_in_the_blanks' && !essay_grading.essay_assignment.meta['fill_in_the_blanks_visible']
              next;
            end

            if question['type'] == 'fill_in_the_blanks'
              pdf.text "Q#{index + 1}. Fill in the blanks", size: 14, style: :bold
              pdf.move_down 8

              # Chosen Paragraphs
              if question['chosen_paragraphs'].present?
                pdf.text "Chosen Paragraphs:", size: 12, style: :bold
                pdf.move_down 3
                pdf.text question['chosen_paragraphs'], size: 11, leading: 4
                pdf.move_down 8
              end

              # Summary (渲染后的，将 [[blank_X]] 替换为下划线)
              if question['summary'].present?
                pdf.text "Summary:", size: 12, style: :bold
                pdf.move_down 3
                summary_text = render_fill_in_the_blank_summary(question)
                pdf.text summary_text, size: 11, leading: 4
                pdf.move_down 8
              end

              # User Answer (格式化后的)
              user_answer_text = get_fill_in_the_blanks_user_answer(question)
              pdf.text "My answer: #{user_answer_text}", size: 12, style: :bold
              pdf.move_down 5

              # Correct Answer (格式化后的)
              correct_answer_text = get_fill_in_the_blanks_answer(question)
              pdf.fill_color '008000'
              pdf.text "Correct answer: #{correct_answer_text}", size: 12, style: :bold
              pdf.fill_color '000000'
              pdf.move_down 15
            else
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

      def generate_listening_pdf(json_data, essay_grading, school_logo_url = nil, _submission_info = nil)
        Prawn::Document.new(page_size: 'A4', margin: [40, 40, 88, 40]) do |pdf|
          font_path = Rails.root.join('app/assets/fonts')

          pdf.font_families.update(
            'NotoSans' => {
              normal: font_path.join('NotoSansTC-Regular.ttf'),
              bold: font_path.join('NotoSansTC-Bold.ttf')
            },
            'DejaVuSans' => {
              normal: font_path.join('DejaVuSans.ttf'),
              bold: font_path.join('DejaVuSans.ttf'),
              italic: font_path.join('DejaVuSans.ttf'),
              bold_italic: font_path.join('DejaVuSans.ttf')
            },
            'Arial' => {
              normal: font_path.join('ARIAL.ttf'),
              bold: font_path.join('ARIALBD.ttf'),
              italic: font_path.join('ARIAL.ttf'),
              bold_italic: font_path.join('ARIALBD.ttf')
            }
          )

          pdf.font('Arial')
          pdf.fallback_fonts(%w[NotoSans DejaVuSans])
          pdf.fill_color '000000'
          draw_standard_report_footer(pdf)

          render_school_logo(pdf, school_logo_url)

          pdf.text "Assessment Report (#{essay_grading.category.humanize})", size: 20, style: :bold, align: :center
          pdf.stroke_color '444444'
          pdf.move_down 25

          pdf.text 'Assignment Information', size: 15, style: :bold
          pdf.stroke_horizontal_rule
          pdf.move_down 12

          listening = json_data['listening'] || {}
          listening_questions = Array(json_data['listening_questions']).presence || Array(listening['questions'])
          info_data = [
            ['Assignment:', json_data['assignment'] || 'N/A'],
            ['Topic:', json_data['topic'] || 'N/A'],
            ['Account:', essay_grading.general_user.show_in_report_name || 'N/A'],
            ['Level:', json_data['level'] || 'N/A'],
            ['Play Count:', (json_data['listening_play_count'] || 0).to_s]
          ]

          info_data.each do |label, value|
            pdf.formatted_text [
              { text: label, styles: [:bold], size: 12 },
              { text: " #{value}", size: 12 }
            ]
            pdf.move_down 4
          end
          pdf.move_down 20

          if json_data['article'].present?
            pdf.text 'Listening Passage', size: 15, style: :bold
            pdf.stroke_horizontal_rule
            pdf.move_down 10
            pdf.text json_data['article'].to_s.gsub("\n", '<br>'), size: 12, leading: 4, inline_format: true
            pdf.move_down 10
          end

          pdf.text 'Listening Questions', size: 18, style: :bold
          pdf.move_down 10

          listening_questions.each_with_index do |question, index|
            pdf.text "#{index + 1}. #{question['question']}", size: 14, style: :bold
            pdf.move_down 5

            if question['type'] == 'multiple_choice' && question['options'].is_a?(Hash)
              question['options'].each do |key, option|
                pdf.text "  #{key}: #{option}", size: 12
              end
              pdf.move_down 5
            end

            pdf.fill_color '000000'
            pdf.text "My Answer: #{question['user_answer'].presence || 'N/A'}", style: :bold, size: 12
            pdf.fill_color '008000'
            pdf.text "Correct Answer: #{question['answer'].presence || 'N/A'}", style: :bold, size: 12
            pdf.fill_color '000000'

            if question['indicator'].present?
              pdf.move_down 4
              pdf.text "Indicator: #{question['indicator']}", size: 11
            end

            pdf.move_down 14
          end

          pdf.text 'Final Result', size: 15, style: :bold
          pdf.stroke_horizontal_rule
          pdf.move_down 10
          pdf.formatted_text [
            { text: 'Overall Score: ', styles: [:bold], size: 12 },
            { text: "#{listening['score'] || 0} / #{listening['full_score'] || 0}", size: 12 }
          ]
          pdf.move_down 5
          pdf.formatted_text [
            { text: 'Percentage: ', styles: [:bold], size: 12 },
            { text: "#{listening['percentage'] || 0}%", size: 12 }
          ]
          pdf.move_down 20
        end
      end

      def generate_sentence_builder_pdf(json_data, essay_grading, school_logo_url = nil, _submission_info = nil)
        Prawn::Document.new(page_size: 'A4', margin: [40, 40, 88, 40]) do |pdf|
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
          draw_standard_report_footer(pdf)

          render_school_logo(pdf, school_logo_url)

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

      def generate_essay_pdf(json_data, essay_grading, school_logo_url = nil, _submission_info = nil, report_type = 'full')
        Prawn::Document.new(page_size: 'A4', margin: [40, 40, 88, 40]) do |pdf|
          font_path = Rails.root.join('app/assets/fonts')
          palette = essay_report_palette

          pdf.font_families.update(
            'NotoSans' => {
              normal: font_path.join('NotoSansTC-Regular.ttf'),
              bold: font_path.join('NotoSansTC-Bold.ttf')
            },
            'DejaVuSans' => {
              normal: font_path.join('DejaVuSans.ttf')
            },
            'Arial' => {
              normal: font_path.join('ARIAL.ttf'),
              bold: font_path.join('ARIALBD.ttf')
            }
          )

          pdf.font('Arial')
          pdf.fallback_fonts(%w[NotoSans DejaVuSans])
          pdf.fill_color '000000'
          sentences = JSON.parse(json_data.dig('data', 'text').to_s) rescue {}
          score_payload = extract_essay_report_score_payload(json_data['score'], sentences)
          draw_essay_report_footer(pdf, palette)
          draw_essay_report_header(pdf, palette, school_logo_url)
          draw_essay_report_info_grid(
            pdf,
            palette,
            assignment_label: json_data['assignment'].presence || 'Essay',
            rubric_label: json_data['rubric'].presence || essay_grading.essay_assignment.rubric['name'].to_s,
            account_label: essay_grading.general_user.show_in_report_name.to_s,
            level_label: json_data['level'].presence || essay_grading.essay_assignment.level.presence || 'N/A',
            overall_score_label: extract_overall_score_label(score_payload),
            report_label: report_type == 'simplified' ? 'Simplified Report' : 'Full Report'
          )
          draw_essay_report_title_box(pdf, palette, json_data['topic'])

          graph_image_url = extract_task1_graph_image_url(essay_grading.essay_assignment, json_data)
          if graph_image_url.present?
            draw_essay_report_section_title(pdf, palette, 'Reference Chart/Graph')
            draw_essay_report_task1_image(pdf, graph_image_url)
          end

          section_index = 1

          if report_type == 'full'
            draw_essay_report_grammar(pdf, palette, sentences, essay_grading, section_index)
            section_index += 1
          end

          draw_essay_report_general_context(
            pdf,
            palette,
            json_data,
            section_index,
            fallback_text: sentences['Overall coherence']
          )
          section_index += 1

          if json_data['revised_essay'].present?
            draw_essay_report_revised_essay(pdf, palette, json_data['revised_essay'], section_index)
            section_index += 1
          end

          draw_essay_report_score(
            pdf,
            palette,
            score_payload,
            section_index,
            simplified: report_type == 'simplified'
          )
        end
      end

      def essay_report_palette
        {
          primary: '1F3A5F',
          accent: 'D9E6F2',
          soft: 'F7FAFC',
          text: '000000',
          muted: '52606D',
          border: 'D9E6F2'
        }
      end

      def draw_essay_report_header(pdf, palette, school_logo_url)
        header_left = pdf.bounds.left
        header_right = pdf.bounds.right
        header_top = pdf.bounds.top
        header_height = 86
        has_logo = school_logo_url.present?
        logo_panel_width = has_logo ? 138 : 0
        logo_panel_x = header_right - logo_panel_width
        blue_width = has_logo ? (logo_panel_x - header_left) : pdf.bounds.width

        pdf.fill_color palette[:primary]
        pdf.fill_rectangle [header_left, header_top], blue_width, header_height

        if has_logo
          pdf.fill_color 'FFFFFF'
          pdf.fill_rectangle [logo_panel_x, header_top], logo_panel_width, header_height

          begin
            logo_tempfile = URI.open(school_logo_url)
            pdf.bounding_box([logo_panel_x + 8, header_top - 6], width: logo_panel_width - 16, height: header_height - 12) do
              pdf.image logo_tempfile,
                        fit: [pdf.bounds.width, pdf.bounds.height],
                        position: :center,
                        vposition: :center
            end
          rescue StandardError => e
            Rails.logger.error("Error loading school logo: #{e.message}")
          end
        end

        pdf.fill_color 'FFFFFF'
        pdf.text_box 'AI English Assessment Report',
                     at: [header_left + 18, header_top - 10],
                     width: blue_width - 36,
                     height: header_height - 20,
                     size: 22,
                     style: :bold,
                     valign: :center

        pdf.fill_color palette[:text]
        pdf.move_cursor_to header_top - header_height - 22
      end

      def draw_essay_report_info_grid(pdf, palette, assignment_label:, rubric_label:, account_label:, level_label:, overall_score_label:, report_label:)
        table_data = [
          [
            { content: "<b>Assignment</b><br/>#{assignment_label}", inline_format: true },
            { content: "<b>Rubric</b><br/>#{rubric_label}", inline_format: true }
          ],
          [
            { content: "<b>Account</b><br/>#{account_label}", inline_format: true },
            { content: "<b>Level</b><br/>#{level_label}", inline_format: true }
          ],
          [
            { content: "<b>Overall Score</b><br/>#{overall_score_label}", inline_format: true },
            { content: "<b>Report Type</b><br/>#{report_label}", inline_format: true }
          ]
        ]

        pdf.table(
          table_data,
          width: pdf.bounds.width,
          column_widths: [pdf.bounds.width / 2.0, pdf.bounds.width / 2.0],
          cell_style: {
            background_color: palette[:soft],
            border_color: palette[:border],
            border_width: 0.8,
            padding: [10, 18, 10, 18],
            inline_format: true,
            size: 10,
            text_color: palette[:text],
            valign: :center,
            leading: 0
          }
        ) do
          cells.style(leading: 0, valign: :center)
          rows(0..2).style(height: 48)
        end
        pdf.move_down 18
      end

      def draw_essay_report_title_box(pdf, palette, topic)
        pdf.fill_color palette[:primary]
        pdf.text 'Title', size: 13, style: :bold
        pdf.fill_color palette[:text]
        pdf.move_down 8

        content = topic.to_s
        content_width = pdf.bounds.width - 28
        content_height = pdf.height_of(content, width: content_width, size: 11, leading: 0)
        box_height = content_height + 20

        pdf.fill_color palette[:soft]
        pdf.stroke_color palette[:border]
        pdf.rounded_rectangle [pdf.bounds.left, pdf.cursor], pdf.bounds.width, box_height, 10
        pdf.fill_and_stroke
        pdf.fill_color palette[:text]
        pdf.bounding_box([pdf.bounds.left + 14, pdf.cursor - 10], width: content_width, height: content_height) do
          pdf.text content, size: 11, leading: 0, color: '000000'
        end
        pdf.move_down(box_height - 4)
        pdf.move_down 22
      end

      def generate_speaking_pronunciation_pdf(json_data, essay_grading, school_logo_url = nil, _submission_info = nil)
        Prawn::Document.new(page_size: 'A4', margin: [40, 40, 88, 40]) do |pdf|
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
          draw_standard_report_footer(pdf)

          render_school_logo(pdf, school_logo_url)

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

      def generate_report(grading, report_type = 'full')
        grading = EssayGrading.includes(:essay_assignment).find(grading.id)
        json_data = prepare_report_data(grading, report_type)
        pdf = generate_pdf(json_data, grading, report_type)
        pdf.render
      end

      def generate_pdf(json_data, essay_grading, report_type = 'full')
        assignment = essay_grading.essay_assignment
        raise "Essay assignment not found for grading ID #{essay_grading.id}" if assignment.nil?

        # 獲取用戶
        user = essay_grading.general_user

        # 只有 AI English 用戶才會有學校 logo
        school_logo_url = user.aienglish_user? ? user.school_logo_url(:small) : nil
        @report_logo_cache ||= {}

        # 準備用戶顯示資訊（優先使用提交班級資訊）
        submission_info = prepare_submission_info(essay_grading)

        # 根據不同類型生成不同報告
        if assignment.category == 'comprehension'
          generate_comprehension_pdf(json_data, essay_grading, school_logo_url, submission_info)
        elsif assignment.category == 'listening'
          generate_listening_pdf(json_data, essay_grading, school_logo_url, submission_info)
        elsif assignment.category == 'speaking_pronunciation' # 新增對 speaking_pronunciation 的專門處理
          generate_speaking_pronunciation_pdf(json_data, essay_grading, school_logo_url, submission_info)
        elsif assignment.category.include?('essay')
          generate_essay_pdf(json_data, essay_grading, school_logo_url, submission_info, report_type)
        elsif assignment.category.include?('sentence_builder')
          generate_sentence_builder_pdf(json_data, essay_grading, school_logo_url, submission_info)
        elsif assignment.category.include?('speaking_conversation')
          generate_essay_pdf(json_data, essay_grading, school_logo_url, submission_info, report_type)
        else
          generate_pdf_from_json(json_data)
        end
      end

      def prepare_report_data(essay_grading, report_type = 'full')
        assignment = essay_grading.essay_assignment
        json_data = {
          'topic' => assignment.topic,
          'account' => essay_grading.general_user.show_in_report_name,
          'assignment' => assignment.assignment,
          'rubric' => assignment.rubric['name'],
          'level' => assignment.level.presence || assignment.meta['level'].presence,
          'graph_image_url' => extract_task1_graph_image_url(assignment),
          'report_type' => report_type
        }

        if assignment.category == 'comprehension'
          json_data['comprehension'] = essay_grading.grading['comprehension']
          newsfeed = cached_news_feed(essay_grading, @news_feed_cache ||= {})
          if newsfeed.present?
            json_data['title'] = extract_news_feed_title(newsfeed)
            json_data['article'] = extract_news_feed_body(newsfeed)
          end
        elsif assignment.category == 'listening'
          listening_payload = essay_grading.grading['listening'].is_a?(Hash) ? essay_grading.grading['listening'] : {}
          json_data['listening'] = listening_payload
          json_data['listening_questions'] = Array(listening_payload['questions']).presence ||
                                             Array(assignment.meta['listening_questions'])
          json_data['listening_play_count'] = listening_payload['play_count'] || 0
          json_data['level'] = listening_payload['level'].presence ||
                               assignment.meta.dig('listening', 'level').presence ||
                               assignment.level.presence ||
                               assignment.meta['level'].presence

          newsfeed = cached_news_feed(essay_grading, @news_feed_cache ||= {})
          if newsfeed.present?
            json_data['title'] = extract_news_feed_title(newsfeed)
            json_data['article'] = extract_news_feed_body(newsfeed)
          end

          json_data['article'] ||= assignment.meta['listening_transcript'].presence ||
                                   assignment.meta.dig('listening', 'transcript').presence ||
                                   sanitize_report_transcript(assignment.meta['listening_ssml_transcript'])
        elsif assignment.category.include?('essay') || assignment.category == 'speaking_conversation'
          json_data.merge!(essay_grading.grading)
          if essay_grading.general_context['data'].present?

            text = essay_grading.general_context['data']['text']
            fixed_json = fix_json_newlines(text)

            begin
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
                json_data['general_context_sections'] =
                  general_context['studentFeedback']['sections'] if general_context['studentFeedback']['sections'].present?
              end
            rescue JSON::ParserError => e
              # JSON 解析失败时尝试正则回退提取（处理 AI 返回的含未转义引号、字面换行等畸形 JSON）
              fallback = extract_general_context_fallback(text)
              if fallback.present?
                json_data['overall_comment'] = fallback['overall'] if fallback['overall'].present?
                json_data['detailedFeedback'] = fallback['detailedFeedback'] if fallback['detailedFeedback'].present?
              end
              Rails.logger.warn("Failed to parse general_context JSON for essay_grading #{essay_grading.id}, used fallback extraction: #{e.message}")
            end
          end
        end

        json_data
      end

      # 批量下载时同一个 newsfeed_id 只获取一次，降低重复查询/请求
      def cached_news_feed(essay_grading, cache = nil)
        unless cache.is_a?(Hash)
        #   puts "[download_reports][newsfeed] no-cache grading_id=#{essay_grading.id} newsfeed_id=#{essay_grading.newsfeed_id}"
          return essay_grading.get_news_feed
        end

        key = essay_grading.newsfeed_id.presence || essay_grading.meta&.dig('newsfeed_id')
        if key.blank?
        #   puts "[download_reports][newsfeed] blank-key grading_id=#{essay_grading.id} newsfeed_id=#{essay_grading.newsfeed_id}"
          return essay_grading.get_news_feed
        end

        if cache.key?(key)
        #   puts "[download_reports][newsfeed] HIT key=#{key} grading_id=#{essay_grading.id}"
          return cache[key]
        end

        #   puts "[download_reports][newsfeed] MISS key=#{key} grading_id=#{essay_grading.id} => fetching"
        cache[key] = essay_grading.get_news_feed
      end

      # 批量下载保留 logo 时，按 URL 缓存二进制，避免重复远程下载
      def render_school_logo(pdf, school_logo_url)
        unless school_logo_url.present?
          pdf.move_down 20
          return
        end

        cache = @report_logo_cache
        logo_binary = nil
        cache_key = begin
          uri = URI.parse(school_logo_url)
          if uri.host.present? && uri.path.present?
            "#{uri.scheme}://#{uri.host}#{uri.path}"
          else
            school_logo_url
          end
        rescue StandardError
          school_logo_url
        end

        if cache.is_a?(Hash) && cache.key?(cache_key)
        #   puts "[download_reports][logo] HIT key=#{cache_key}"
          logo_binary = cache[cache_key]
        else
        #   puts "[download_reports][logo] MISS key=#{cache_key} url=#{school_logo_url} => downloading"
          begin
            require 'open-uri'
            logo_binary = URI.open(school_logo_url, &:read)
            cache[cache_key] = logo_binary if cache.is_a?(Hash)
          rescue StandardError => e
            Rails.logger.error("Error loading school logo: #{e.message}")
          end
        end

        if logo_binary.present?
          pdf.image StringIO.new(logo_binary), at: [0, pdf.cursor], width: 50
          pdf.move_down 20
        elsif !cache.is_a?(Hash)
          # 单份下载时失败保持旧行为：不额外位移
          nil
        end
      end

      def normalized_report_type
        params[:report_type] == 'simplified' ? 'simplified' : 'full'
      end

      def extract_news_feed_title(newsfeed)
        news_feed_payload(newsfeed)['title']
      end

      def extract_news_feed_body(newsfeed)
        payload = news_feed_payload(newsfeed)
        payload['content'].presence ||
          payload['text'].presence ||
          payload['transcript'].presence ||
          sanitize_report_transcript(payload['ssml_transcript']) ||
          payload['plain_transcript'].presence
      end

      def news_feed_payload(newsfeed)
        return {} unless newsfeed.is_a?(Hash)

        payload = newsfeed['data']
        payload.is_a?(Hash) ? payload : newsfeed
      end

      def sanitize_report_transcript(value)
        text = value.to_s
        return nil if text.blank?

        stripped = text.gsub(/<[^>]+>/, ' ').gsub(/\s+/, ' ').strip
        stripped.presence
      end

      def draw_essay_report_task1_image(pdf, image_url)
        return if image_url.blank?

        begin
          chart_image = URI.open(image_url)
          pdf.image chart_image, fit: [pdf.bounds.width, 220], position: :center
          pdf.move_down 24
        rescue StandardError => e
          Rails.logger.error("Error loading IELTS Task 1 image: #{e.message}")
        end
      end

      def draw_essay_report_section_title(pdf, palette, title)
        pdf.fill_color palette[:primary]
        pdf.text title, size: 15, style: :bold
        pdf.fill_color palette[:text]
        pdf.stroke_color palette[:border]
        pdf.move_down 6
        pdf.stroke_horizontal_rule
        pdf.move_down 10
      end

      def draw_essay_report_grammar(pdf, palette, sentences, essay_grading, section_index)
        draw_essay_report_section_title(pdf, palette, "Section #{to_roman(section_index)}: Grammar")

        pdf.indent(20) do
          grammar_sentence_entries(sentences).each do |key, value|
            pdf.text "#{key}:", size: 12, style: :bold, color: palette[:text]
            pdf.move_down 4

            sentence_text = value['sentence'].to_s
            normalized_errors = grammar_error_entries(value['errors'])

            formatted_text = sentence_text.dup
            normalized_errors.each do |_, error_value|
              error_word = error_value['word'].to_s
              next if error_word.blank?

              formatted_text.gsub!(/\b#{Regexp.escape(error_word)}\b/) do |match|
                "<color rgb='FF0000'>#{match}</color>"
              end
            end

            pdf.text formatted_text, size: 11, inline_format: true, color: palette[:text]
            pdf.move_down 8

            if normalized_errors.any?
              pdf.indent(16) do
                normalized_errors.each do |_, error_value|
                  category_display = convert_category(essay_grading.essay_assignment.category, error_value['category'])
                  correction = error_value['corr'].to_s
                  if correction.include?('->')
                    correct_word = correction.split('->').last.to_s.strip
                    pdf.text "<b>Mistake: #{error_value['word']} -> #{correct_word} <color rgb='1F3A5F'>(#{category_display})</color></b>",
                             size: 10.5, inline_format: true, color: palette[:text]
                  else
                    pdf.text "<b>Mistake: #{error_value['word']} <color rgb='1F3A5F'>(#{category_display})</color></b>",
                             size: 10.5, inline_format: true, color: palette[:text]
                  end
                  pdf.move_down 3
                  pdf.text error_value['explanation'].to_s, size: 10, color: palette[:text]
                  pdf.move_down 8
                end
              end
            end

            pdf.move_down 14
          end
        end

        pdf.move_down 18
      end

      def grammar_sentence_entries(sentences)
        return [] unless sentences.is_a?(Hash)

        sentences
          .select { |key, value| key.to_s.start_with?('Sentence', 'sentence') && value.is_a?(Hash) }
          .sort_by do |key, _|
            numeric_part = key.to_s.match(/(\d+)/)&.captures&.first
            numeric_part.present? ? numeric_part.to_i : Float::INFINITY
          end
      end

      def grammar_error_entries(errors)
        return {} unless errors.is_a?(Hash) && errors.present?

        normalized_errors =
          if errors.keys.first.to_s.start_with?('error')
            errors
          else
            { 'error1' => errors }
          end

        normalized_errors.sort_by do |key, _|
          numeric_part = key.to_s.match(/(\d+)/)&.captures&.first
          numeric_part.present? ? numeric_part.to_i : Float::INFINITY
        end
      end

      def draw_essay_report_general_context(pdf, palette, json_data, section_index, fallback_text:)
        draw_essay_report_section_title(pdf, palette, "Section #{to_roman(section_index)}: Overall Comments")

        overall_text = json_data['overall_comment'].presence || json_data['general_context'].presence || fallback_text.presence
        section_titles = {
          'content' => 'Content',
          'organisation' => 'Organisation',
          'oneStrength' => 'One Strength',
          'oneKeyAreaForImprovement' => 'One Key Area for Improvement',
          'logicAndCoherence' => 'Logic & Coherence'
        }

        if json_data['general_context_sections'].present?
          if overall_text.present?
            pdf.text overall_text.to_s, size: 12, leading: 5, color: palette[:text]
            pdf.move_down 14
          end

          section_titles.each do |key, label|
            value = json_data['general_context_sections'][key]
            next if value.blank?

            pdf.text label, size: 12, style: :bold, color: palette[:text]
            pdf.move_down 4
            draw_essay_report_bullets(pdf, normalize_report_points(value))
            pdf.move_down 10
          end
        elsif json_data['detailedFeedback'].present?
          if overall_text.present?
            pdf.text 'Overall Feedback', size: 12, style: :bold, color: palette[:text]
            pdf.move_down 4
            pdf.text overall_text.to_s, size: 12, leading: 5, color: palette[:text]
            pdf.move_down 14
          end

          pdf.text 'Detailed Feedback', size: 12, style: :bold, color: palette[:text]
          pdf.move_down 4
          pdf.text json_data['detailedFeedback'].to_s, size: 12, leading: 5, color: palette[:text]
        elsif overall_text.present?
          pdf.text 'Overall Feedback', size: 12, style: :bold, color: palette[:text]
          pdf.move_down 4
          pdf.text overall_text.to_s, size: 12, leading: 5, color: palette[:text]
        end

        pdf.move_down 18
      end

      def draw_essay_report_revised_essay(pdf, palette, revised_essay, section_index)
        draw_essay_report_section_title(pdf, palette, "Section #{to_roman(section_index)}: Revised Essay")
        revised_essay.to_s.split("\n\n").each do |paragraph|
          next if paragraph.strip.blank?

          pdf.text paragraph, size: 12, leading: 6, color: palette[:text]
          pdf.move_down 10
        end
        pdf.move_down 18
      end

      def draw_essay_report_score(pdf, palette, score_payload, section_index, simplified:)
        title = simplified ? 'Score' : 'Score Breakdown'
        draw_essay_report_section_title(pdf, palette, "Section #{to_roman(section_index)}: #{title}")
        return if score_payload[:overall_score].blank?

        pdf.fill_color palette[:primary]
        pdf.text "Overall Score #{extract_overall_score_label(score_payload)}", size: 16, style: :bold, align: :center
        pdf.fill_color palette[:text]
        pdf.move_down 14

        rows = extract_score_rows(score_payload)

        if simplified
          rows.each do |row|
            pdf.text "• #{row[:criterion]}: #{row[:score_label]}", size: 11, color: palette[:text]
            pdf.move_down 4
          end
        else
          table_rows = [['Criterion', 'Score', 'Feedback']] + rows.map { |row| [row[:criterion], row[:score_label], row[:comment].to_s] }
          pdf.table(
            table_rows,
            header: true,
            width: pdf.bounds.width,
            cell_style: { size: 10, padding: 8, border_color: palette[:border], text_color: palette[:text], valign: :center, leading: 0 }
          ) do
            row(0).background_color = palette[:primary]
            row(0).text_color = 'FFFFFF'
            row(0).font_style = :bold
            columns(0).width = 170
            columns(1).width = 60
            columns(2).width = pdf.bounds.width - 230
            columns(1).align = :center
          end
        end
      end

      def draw_essay_report_bullets(pdf, points)
        pdf.indent(12) do
          points.each do |point|
            pdf.formatted_text [
              { text: '• ', color: '000000', styles: [:bold], size: 11 },
              { text: point.to_s, color: '000000', size: 10.5 }
            ], leading: 3
            pdf.move_down 4
          end
        end
      end

      def draw_essay_report_footer(pdf, _palette)
        pdf.repeat(:all, dynamic: true) do
          pdf.canvas do
            pdf.fill_color '000000'
            pdf.text_box "Page #{pdf.page_number}",
                         at: [pdf.bounds.right - 104, 50],
                         width: 58,
                         height: 12,
                         size: 8,
                         align: :right,
                         valign: :center
          end
        end
      end

      def draw_standard_report_footer(pdf)
        pdf.repeat(:all, dynamic: true) do
          pdf.canvas do
            pdf.fill_color '000000'
            pdf.text_box "Page #{pdf.page_number}",
                         at: [pdf.bounds.right - 104, 50],
                         width: 58,
                         height: 12,
                         size: 8,
                         align: :right,
                         valign: :center
          end
        end
      end

      def normalize_report_points(value)
        return value if value.is_a?(Array)

        value.to_s
             .split(/\r?\n+/)
             .map { |line| line.to_s.gsub(/\A[•●\-\*]\s*/, '').strip }
             .reject(&:blank?)
      end

      def extract_essay_report_score_payload(*sources)
        sources.each do |source|
          normalized = normalize_essay_report_score_payload(source)
          return normalized if normalized[:overall_score].present? || normalized[:criteria].present?
        end

        {
          overall_score: nil,
          full_score: nil,
          criteria: []
        }
      end

      def normalize_essay_report_score_payload(source)
        source_hash = source.is_a?(Hash) ? source.deep_stringify_keys : {}
        return normalize_nested_score_payload(source_hash) if source_hash['criteria'].is_a?(Hash) || source_hash['overall_score'].present?

        normalize_legacy_score_payload(source_hash)
      end

      def normalize_nested_score_payload(source_hash)
        criteria_rows = source_hash.fetch('criteria', {}).each_with_object([]) do |(criterion_name, criterion_value), rows|
          next unless criterion_value.is_a?(Hash)

          normalized_value = criterion_value.deep_stringify_keys
          criterion_score = normalized_value['score'].presence || normalized_value['value'].presence || normalized_value['points'].presence
          criterion_full_score = normalized_value['full_score'].presence || source_hash['full_score'].presence
          criterion_comment = normalized_value['comment'].presence || normalized_value['feedback'].presence || normalized_value['explanation'].presence

          rows << {
            criterion: criterion_name.to_s,
            score_label: build_score_label(criterion_score, criterion_full_score),
            comment: criterion_comment.to_s
          }
        end

        {
          overall_score: source_hash['overall_score'].presence || source_hash['Overall Score'].presence,
          full_score: source_hash['full_score'].presence || source_hash['Full Score'].presence,
          criteria: criteria_rows
        }
      end

      def normalize_legacy_score_payload(source_hash)
        rows = source_hash.each_with_object([]) do |(key, value), result|
          next unless key.to_s.start_with?('Criterion')
          next unless value.is_a?(Hash)

          normalized_value = value.deep_stringify_keys
          full_score = normalized_value['Full Score'].presence || source_hash['Full Score'].presence
          comment = normalized_value['explanation'].presence || normalized_value['comment'].presence || normalized_value['feedback'].presence

          normalized_value.each do |criterion_name, criterion_value|
            next if ['Full Score', 'explanation', 'comment', 'feedback'].include?(criterion_name)

            result << {
              criterion: criterion_name.to_s,
              score_label: build_score_label(criterion_value, full_score),
              comment: comment.to_s
            }
          end
        end

        {
          overall_score: source_hash['Overall Score'].presence || source_hash['overall_score'].presence,
          full_score: source_hash['Full Score'].presence || source_hash['full_score'].presence,
          criteria: rows
        }
      end

      def build_score_label(score, full_score)
        return score.to_s if full_score.blank?
        return full_score.to_s if score.blank?

        "#{score} / #{full_score}"
      end

      def extract_score_rows(score_payload)
        Array(score_payload[:criteria])
      end

      def extract_overall_score_label(score_payload)
        return 'N/A' if score_payload[:overall_score].blank?

        build_score_label(score_payload[:overall_score], score_payload[:full_score])
      end

      def extract_task1_graph_image_url(assignment, json_data = nil)
        candidates = [
          json_data&.dig('graph_image_url'),
          assignment.try(:graph_image_url),
          assignment.meta['graph_image_url'],
          assignment.meta.dig('ielts_task1', 'graph_image_url'),
          assignment.meta.dig('ielts_task1', 'graph_file_url'),
          assignment.meta.dig('self_upload_newsfeed', 'graph_image_url')
        ]

        candidates.compact.find(&:present?)
      rescue StandardError
        nil
      end

      def to_roman(number)
        {
          1 => 'I',
          2 => 'II',
          3 => 'III',
          4 => 'IV',
          5 => 'V'
        }[number] || number.to_s
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

      # 当 general_context JSON 解析失败时的回退提取（处理 AI 返回的含未转义引号、字面换行等畸形 JSON）
      def extract_general_context_fallback(text)
        result = {}
        return result if text.blank?

        # 提取 overall（通常不含内部引号）
        if text =~ /"overall"\s*:\s*"((?:[^"\\]|\\.)*)"/
          result['overall'] = Regexp.last_match(1).gsub(/\\n/, "\n").gsub(/\\"/, '"')
        end

        # 提取 detailedFeedback（可能含内部引号，用 [\s\S]* 匹配含换行的内容，贪婪到结构末尾）
        if text =~ /"detailedFeedback"\s*:\s*"([\s\S]*)"\s*\n\s*}\s*\n\s*}/
          result['detailedFeedback'] = Regexp.last_match(1).gsub(/\\n/, "\n").gsub(/\\"/, '"')
        end

        result
      end

      # 渲染填空题的 summary，将 [[blank_X]] 替换为下划线
      def render_fill_in_the_blank_summary(question)
        return '' unless question['summary']

        summary = question['summary']
        # 匹配 [[blank_X]] 格式
        blank_regex = /\[\[(\w+)\]\]/
        # 将所有 [[blank_X]] 替换为下划线
        summary.gsub(blank_regex, '____')
      end

      # 获取填空题的用户答案，按照 blanks 的顺序排列，用逗号分隔
      def get_fill_in_the_blanks_user_answer(question)
        return '' unless question['user_answer'] && question['blanks'] && question['blanks'].is_a?(Array)

        begin
          # 解析 user_answer JSON 字符串
          user_answers = if question['user_answer'].is_a?(String)
                           JSON.parse(question['user_answer'])
                         else
                           question['user_answer']
                         end

          # 按照 blanks 的顺序排列答案
          answers = question['blanks'].map do |blank|
            blank_id = blank['id']
            user_answer = user_answers[blank_id]

            # 如果有答案，返回去除首尾空格的答案；否则返回下划线
            user_answer ? user_answer.to_s.strip : '__'
          end

          # 用逗号分隔
          answers.join(', ')
        rescue JSON::ParserError => e
          # 如果解析失败，返回原始值
          Rails.logger.warn("Failed to parse user_answer: #{e.message}")
          question['user_answer'].to_s
        end
      end

      # 获取填空题的正确答案，按照 blanks 的顺序排列，用逗号分隔
      def get_fill_in_the_blanks_answer(question)
        return '' unless question['blanks'] && question['blanks'].is_a?(Array)

        question['blanks'].map { |blank| blank['answer'] }.join(', ')
      end

      # 更新作業分配狀態（如果存在對應的分配記錄）
      def update_assignment_status_if_needed
        # 查找對應的 AssignmentStudentAssignment
        assignment = AssignmentStudentAssignment.find_by(
          essay_assignment_id: @essay_assignment.id,
          general_user_id: current_general_user.id
        )

        # 如果存在分配記錄，說明是通過分配的作業進入，需要更新狀態
        if assignment
          assignment.update_columns(
            status: AssignmentStudentAssignment.statuses[:completed],
            completed_at: @essay_grading.created_at
          )
          Rails.logger.info "Updated assignment status for user #{current_general_user.id}, assignment #{@essay_assignment.id}"
        else
          # 如果不存在分配記錄，說明是直接通過 code 進入，不需要更新狀態
          Rails.logger.info "No assignment distribution found for user #{current_general_user.id}, assignment #{@essay_assignment.id} - skipping status update"
        end
      end

    end
  end
end
