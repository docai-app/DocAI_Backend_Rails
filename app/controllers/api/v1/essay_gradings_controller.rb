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
          draw_standard_report_footer(pdf)

          user = @essay_grading.general_user
          school_logo_url = user.aienglish_user? ? user.school_logo_url(:small) : nil

          draw_standard_report_logo(pdf, school_logo_url)

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

        # binding.pry
        grading_json = effective_score_sentences(@essay_grading)
        scores = extract_scores_from_sentences(grading_json)

        if @essay_grading.category == 'comprehension'
          score = @essay_grading.grading.dig('comprehension', 'score'),
                  full_score = @essay_grading.grading.dig('comprehension', 'full_score')
        elsif @essay_grading.category == 'speaking_pronunciation'
          score = @essay_grading['score']
          full_score = 100
          # binding.pry
        else
          score = grading_json['Overall Score'] || @essay_grading.grading['score']
          full_score = grading_json['Full Score'] || @essay_grading.grading['full_score']
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
            revised_essay: @essay_grading.revised_essay,
            teacher_review: @essay_grading.teacher_review_hash,
            teacher_review_history: teacher_can_edit_review?(@essay_grading) ? @essay_grading.teacher_review_history_array : [],
            essay: @essay_grading.essay,
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
              essay_type: @essay_grading.essay_assignment.essay_type,
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
        return if performed? || @essay_assignment.nil?

        puts "set_essay_assignment_by_code: #{@essay_assignment.inspect}"

        grading_params = essay_grading_params
        prepared_attachment = prepare_audio_attachment_for_persistence(
          category: @essay_assignment.category,
          uploaded_file: grading_params[:file]
        )

        @essay_grading = @essay_assignment.essay_gradings.new(
          essay_grading_attributes_for_persistence(@essay_assignment.category, grading_params)
        )
        @essay_grading.general_user = current_general_user
        @essay_grading.topic = @essay_assignment.topic

        if @essay_assignment.rubric.present? && @essay_assignment.rubric['app_key'].present?
          @essay_grading.grading ||= {}
          @essay_grading.grading['app_key'] = @essay_assignment.rubric['app_key']['grading']
          @essay_grading.general_context ||= {}
          @essay_grading.general_context['app_key'] = @essay_assignment.rubric['app_key']['general_context']
          @essay_grading.revised_essay ||= {}
          @essay_grading.revised_essay['app_key'] = @essay_assignment.revised_essay_workflow_app_key
        end

        begin
          EssayGrading.transaction do
            @essay_grading.save!
            persist_uploaded_attachment!(
              essay_grading: @essay_grading,
              category: @essay_assignment.category,
              uploaded_file: grading_params[:file],
              prepared_attachment:
            )
          end

          # Track assignment submission
          # 首先，確保 Ahoy tracker 與當前提交作業的用戶正確關聯
          ahoy.authenticate(current_general_user) if current_general_user
          ahoy.track 'Assignment Submitted',
                     { essay_grading_id: @essay_grading.id, essay_assignment_id: @essay_assignment.id }
          render json: { success: true, data: @essay_grading.id, essay_grading: @essay_grading }, status: :created
        rescue ActiveRecord::RecordInvalid
          render json: { success: false, errors: @essay_grading.errors.full_messages }, status: :unprocessable_entity
        end
      ensure
        prepared_attachment&.close!
      end

      def teacher_review
        set_essay_grading

        unless teacher_can_edit_review?(@essay_grading)
          render json: { success: false, error: 'You do not have permission to edit this grading.' }, status: :forbidden
          return
        end

        teacher_review_payload = build_teacher_review_payload(teacher_review_params.to_h)
        merged_review = @essay_grading.teacher_review_hash.deep_dup

        merged_review['score'] = teacher_review_payload['score'] if teacher_review_payload['score'].present?
        merged_review['grammar'] = teacher_review_payload['grammar'] if teacher_review_payload['grammar'].present?
        merged_review['general_context'] = teacher_review_payload['general_context'] if teacher_review_payload['general_context'].present?
        merged_review['revised_essay'] = teacher_review_payload['revised_essay'] if teacher_review_payload['revised_essay'].present?
        merged_review['confirmed'] = true
        merged_review['confirmed_at'] = Time.current.as_json
        merged_review['confirmed_by'] = {
          'id' => current_general_user.id,
          'email' => current_general_user.email,
          'nickname' => current_general_user.nickname
        }

        next_meta = (@essay_grading.meta || {}).deep_dup
        next_meta['teacher_review'] = merged_review
        history = @essay_grading.teacher_review_history_array.deep_dup
        history << build_teacher_review_history_entry(merged_review)
        next_meta['teacher_review_history'] = history

        if @essay_grading.update(meta: next_meta)
          render json: { success: true, teacher_review: merged_review, teacher_review_history: history }, status: :ok
        else
          render json: { success: false, errors: @essay_grading.errors.full_messages }, status: :unprocessable_entity
        end
      rescue ActionController::ParameterMissing => e
        render json: { success: false, error: e.message }, status: :unprocessable_entity
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      def teacher_review_restore
        set_essay_grading

        unless teacher_can_edit_review?(@essay_grading)
          render json: { success: false, error: 'You do not have permission to edit this grading.' }, status: :forbidden
          return
        end

        next_meta = (@essay_grading.meta || {}).deep_dup
        original_history = @essay_grading.teacher_review_history_array.deep_dup
        history = original_history.deep_dup
        source = params[:source].to_s
        current_review = @essay_grading.teacher_review_hash.deep_dup

        if current_review.present?
          history << build_teacher_review_history_entry(current_review)
        end

        if source == 'ai_original'
          next_meta.delete('teacher_review')
        else
          version_id = params[:version_id].to_s
          selected_version = original_history.find { |item| item.is_a?(Hash) && item['version_id'].to_s == version_id }
          if selected_version.blank?
            render json: { success: false, error: 'Selected teacher review version was not found.' }, status: :not_found
            return
          end

          restored_review = selected_version.deep_dup
          restored_review.delete('version_id')
          restored_review.delete('saved_at')
          restored_review.delete('saved_by')
          restored_review['confirmed'] = true
          restored_review['confirmed_at'] = Time.current.as_json
          restored_review['confirmed_by'] = {
            'id' => current_general_user.id,
            'email' => current_general_user.email,
            'nickname' => current_general_user.nickname
          }
          restored_review['restored_from_version_id'] = version_id
          restored_review['restored_at'] = Time.current.as_json

          next_meta['teacher_review'] = restored_review
          history << build_teacher_review_history_entry(restored_review)
        end

        next_meta['teacher_review_history'] = history

        if @essay_grading.update(meta: next_meta)
          render json: {
            success: true,
            teacher_review: @essay_grading.teacher_review_hash,
            teacher_review_history: history
          }, status: :ok
        else
          render json: { success: false, errors: @essay_grading.errors.full_messages }, status: :unprocessable_entity
        end
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      def update
        set_essay_grading

        grading_params = essay_grading_params

        prepared_attachment = prepare_audio_attachment_for_persistence(
          category: @essay_grading.category,
          uploaded_file: grading_params[:file]
        )

        if prepared_attachment.nil? && should_normalize_existing_speaking_attachment?(@essay_grading, grading_params)
          prepared_attachment = SpeakingAudioAttachmentNormalizerService.normalize_blob(@essay_grading.file.blob)
        end

        begin
          EssayGrading.transaction do
            @essay_grading.update!(
              essay_grading_attributes_for_persistence(@essay_grading.category, grading_params)
            )

            persist_uploaded_attachment!(
              essay_grading: @essay_grading,
              category: @essay_grading.category,
              uploaded_file: grading_params[:file],
              prepared_attachment:
            )
          end

          render json: { success: true, data: @essay_grading.id, essay_grading: @essay_grading }, status: :ok
        rescue ActiveRecord::RecordInvalid
          render json: { success: false, errors: @essay_grading.errors.full_messages }, status: :unprocessable_entity
        end
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :internal_server_error
      ensure
        prepared_attachment&.close!
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

      def set_essay_assignment_by_code
        @essay_assignment = EssayAssignment.find_by!(code: params[:essay_assignment_id])
      rescue ActiveRecord::RecordNotFound
        render json: { success: false, error: 'EssayAssignment not found' }, status: :not_found
      end

      def essay_grading_params
        params.require(:essay_grading).permit(
          :status,
          :essay,
          :topic,
          :file,
          :using_time,
          grading: [
            :app_key,
            {
              comprehension: [
                questions: [
                  :question,
                  :answer,
                  :user_answer,
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
          meta: %i[newsfeed_id],
          sentence_builder: %i[vocab sentence]
        )
      end

      def essay_grading_attributes_for_persistence(category, grading_params)
        category == 'speaking_essay' ? grading_params.except(:file) : grading_params
      end

      def prepare_audio_attachment_for_persistence(category:, uploaded_file:)
        return nil unless category == 'speaking_essay'
        return nil if uploaded_file.blank?

        SpeakingAudioAttachmentNormalizerService.normalize_uploaded_file(uploaded_file)
      end

      def persist_uploaded_attachment!(essay_grading:, category:, uploaded_file:, prepared_attachment:)
        if category == 'speaking_essay'
          return if prepared_attachment.nil?

          essay_grading.file.attach(
            io: prepared_attachment.tempfile,
            filename: prepared_attachment.filename,
            content_type: prepared_attachment.content_type
          )
          raise 'Failed to attach normalized speaking essay audio.' unless essay_grading.file.attached?
          return
        end

        return if uploaded_file.blank?

        essay_grading.file.attach(uploaded_file)
        raise 'Failed to attach uploaded audio file.' unless essay_grading.file.attached?
      end

      def should_normalize_existing_speaking_attachment?(essay_grading, grading_params)
        essay_grading.category == 'speaking_essay' &&
          grading_params[:file].blank? &&
          essay_grading.file.attached? &&
          essay_grading.file.blob.content_type.to_s != 'audio/mp3'
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
          draw_standard_report_footer(pdf)

          draw_standard_report_logo(pdf, school_logo_url)

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
        Prawn::Document.new(page_size: 'A4', margin: [40, 40, 88, 40]) do |pdf|
          font_path = Rails.root.join('app/assets/fonts')

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
          draw_standard_report_footer(pdf)

          draw_standard_report_logo(pdf, school_logo_url)

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
          palette = essay_report_palette
          sentences = JSON.parse(json_data.dig('data', 'text').to_s) rescue {}
          grammar_sentences = effective_grammar_sentences(essay_grading, sentences)
          draw_essay_report_footer(pdf, palette)
          draw_essay_report_header(pdf, palette, school_logo_url)
          draw_essay_report_info_grid(
            pdf,
            palette,
            assignment_label: json_data['assignment'].presence || 'Essay',
            rubric_label: json_data['rubric'].presence || essay_grading.essay_assignment.rubric['name'].to_s,
            account_label: essay_grading.general_user.show_in_report_name.to_s,
            overall_score_label: extract_overall_score_label(sentences)
          )
          draw_essay_report_title_box(pdf, palette, json_data['topic'])
          draw_essay_report_task1_image(pdf, json_data['graph_image_url'])

          section_index = 1

          if report_type == 'full'
            draw_essay_report_grammar(pdf, palette, grammar_sentences, essay_grading, section_index)
            section_index += 1
          end

          draw_essay_report_general_context(
            pdf,
            palette,
            json_data,
            section_index,
            fallback_text: sentences['Overall coherence'].to_s
          )
          section_index += 1

          if essay_grading.essay_assignment.category == 'essay' && json_data['revised_essay'].present?
            draw_essay_report_revised_essay(pdf, palette, json_data['revised_essay'], section_index)
            section_index += 1
          end

          if essay_grading.essay_assignment.category == 'essay'
            draw_essay_report_score(pdf, palette, sentences, section_index, simplified: report_type == 'simplified')
          end
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
          draw_standard_report_footer(pdf)
          draw_standard_report_logo(pdf, school_logo_url)

          pdf.text 'Assessment Report (Listening)', size: 20, style: :bold, align: :center
          pdf.stroke_color '444444'
          pdf.move_down 25

          pdf.text 'Assignment Information', size: 15, style: :bold
          pdf.stroke_horizontal_rule
          pdf.move_down 12

          info_data = [
            ['Assignment:', json_data['assignment'] || 'N/A'],
            ['Title:', json_data['title'] || json_data['topic'] || essay_grading.essay_assignment.title || 'N/A'],
            ['Account:', essay_grading.general_user.show_in_report_name || 'N/A'],
            ['Level:', json_data['level'] || 'N/A'],
            ['Play Count:', json_data['listening_play_count'].to_s]
          ]

          info_data.each do |label, value|
            pdf.formatted_text [
              { text: label, styles: [:bold], size: 12 },
              { text: " #{value}", size: 12 }
            ]
            pdf.move_down 4
          end
          pdf.move_down 25

          if json_data['article'].present?
            pdf.text 'Listening Transcript', size: 15, style: :bold
            pdf.stroke_horizontal_rule
            pdf.move_down 12
            json_data['article'].to_s.split(/\n{2,}/).each do |paragraph|
              next if paragraph.strip.blank?

              pdf.text paragraph.strip, size: 12, leading: 4
              pdf.move_down 10
            end
            pdf.move_down 14
          end

          questions = Array(json_data['listening_questions'])
          if questions.any?
            pdf.text 'Listening Questions', size: 15, style: :bold
            pdf.stroke_horizontal_rule
            pdf.move_down 12

            questions.each_with_index do |question, index|
              next unless question.is_a?(Hash)

              pdf.text "#{index + 1}. #{question['question']}", size: 13, style: :bold
              pdf.move_down 5

              if question['options'].is_a?(Hash)
                question['options'].each do |key, option|
                  pdf.text "  #{key}: #{option}", size: 11
                end
                pdf.move_down 5
              end

              pdf.fill_color '000000'
              pdf.text "My Answer: #{question['user_answer'].presence || 'No answer'}", style: :bold, size: 11
              pdf.fill_color listening_answer_correct_for_report?(question) ? '008000' : 'C62828'
              pdf.text "Correct Answer: #{question['answer']}", style: :bold, size: 11
              pdf.fill_color '000000'
              pdf.move_down 14
            end
          end

          listening = json_data['listening'].is_a?(Hash) ? json_data['listening'] : {}
          pdf.text 'Final Result', size: 15, style: :bold
          pdf.stroke_horizontal_rule
          pdf.move_down 10
          pdf.formatted_text [
            { text: 'Overall Score: ', styles: [:bold], size: 12 },
            { text: "#{listening['score'] || 0} / #{listening['full_score'] || questions.count}", size: 12 }
          ]
          pdf.move_down 30
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
            logo_tempfile = cached_remote_image_io(school_logo_url)
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

      def draw_essay_report_info_grid(pdf, palette, assignment_label:, rubric_label:, account_label:, overall_score_label:)
        table_data = [
          [
            { content: "<b>Assignment</b><br/>#{assignment_label}", inline_format: true },
            { content: "<b>Rubric</b><br/>#{rubric_label}", inline_format: true }
          ],
          [
            { content: "<b>Account</b><br/>#{account_label}", inline_format: true },
            { content: "<b>Overall Score</b><br/>#{overall_score_label}", inline_format: true }
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
          rows(0..1).style(height: 48)
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

      def draw_essay_report_task1_image(pdf, image_url)
        return if image_url.blank?

        begin
          chart_image = cached_remote_image_io(image_url)
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

            pdf.fill_color palette[:text]
            pdf.text "#{key}:", size: 12, style: :bold
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

            pdf.text formatted_text, size: 11, inline_format: true, color: '000000'
            pdf.move_down 8

            if normalized_errors.any?
              pdf.indent(16) do
                normalized_errors.each do |_, error_value|
                  category = error_value['category']
                  error_word = error_value['word']
                  explanation = error_value['explanation']
                  correction = error_value['corr']
                  category_display = convert_category(essay_grading.essay_assignment.category, category)

                  if correction.present? && correction.include?('->')
                    correct_word = correction.split('->').last.to_s.strip
                    pdf.text "<b>Mistake: #{error_word} -> #{correct_word} <color rgb='1F3A5F'>(#{category_display})</color></b>",
                             size: 10.5, inline_format: true, color: '000000'
                  else
                    pdf.text "<b>Mistake: #{error_word} <color rgb='1F3A5F'>(#{category_display})</color></b>",
                             size: 10.5, inline_format: true, color: '000000'
                  end
                  pdf.move_down 3
                  pdf.text explanation.to_s, size: 10, color: '000000'
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
            pdf.text overall_text.to_s, size: 12, leading: 5, color: '000000'
            pdf.move_down 14
          end

          section_titles.each do |key, label|
            value = json_data['general_context_sections'][key]
            next if value.blank?

            pdf.text label, size: 12, style: :bold, color: '000000'
            pdf.move_down 4
            draw_essay_report_bullets(pdf, normalize_report_points(value))
            pdf.move_down 10
          end
        elsif json_data['detailedFeedback'].present?
          if overall_text.present?
            pdf.text "Overall Feedback", size: 12, style: :bold, color: '000000'
            pdf.move_down 4
            pdf.text overall_text.to_s, size: 12, leading: 5, color: '000000'
            pdf.move_down 14
          end

          pdf.text "Detailed Feedback", size: 12, style: :bold, color: '000000'
          pdf.move_down 4
          pdf.text json_data['detailedFeedback'].to_s, size: 12, leading: 5, color: '000000'
        elsif overall_text.present?
          pdf.text "Overall Feedback", size: 12, style: :bold, color: '000000'
          pdf.move_down 4
          pdf.text overall_text.to_s, size: 12, leading: 5, color: '000000'
        end

        pdf.move_down 18
      end

      def draw_essay_report_revised_essay(pdf, palette, revised_essay, section_index)
        draw_essay_report_section_title(pdf, palette, "Section #{to_roman(section_index)}: Revised Essay")
        revised_essay.to_s.split("\n\n").each do |paragraph|
          next if paragraph.strip.blank?

          pdf.text paragraph, size: 12, leading: 6, color: '000000'
          pdf.move_down 10
        end
        pdf.move_down 18
      end

      def draw_essay_report_score(pdf, palette, sentences, section_index, simplified:)
        title = simplified ? 'Score' : 'Score Breakdown'
        draw_essay_report_section_title(pdf, palette, "Section #{to_roman(section_index)}: #{title}")
        return if sentences['Overall Score'].blank?

        overall_score_label = extract_overall_score_label(sentences)
        pdf.fill_color palette[:primary]
        pdf.text "Overall Score #{overall_score_label}", size: 16, style: :bold, align: :center
        pdf.fill_color palette[:text]
        pdf.move_down 14

        rows = extract_score_rows(sentences)

        if simplified
          rows.each do |row|
            pdf.text "• #{row[:criterion]}: #{row[:score_label]}", size: 11, color: '000000'
            pdf.move_down 4
          end
        else
          table_rows = [['Criterion', 'Score', 'Comment']] + rows.map { |row| [row[:criterion], row[:score_label], row[:comment].to_s] }
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

      def draw_essay_report_footer(pdf, palette)
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

      def extract_score_rows(sentences)
        sentences.each_with_object([]) do |(key, value), rows|
          next unless key.to_s.start_with?('Criterion')
          next unless value.is_a?(Hash)

          full_score = value['Full Score'] || 'N/A'
          value.each do |criterion_name, criterion_value|
            next if ['Full Score', 'explanation'].include?(criterion_name)

            rows << {
              criterion: criterion_name,
              score_label: "#{criterion_value} / #{full_score}",
              comment: value['explanation']
            }
          end
        end
      end

      def extract_overall_score_label(sentences)
        return 'N/A' if sentences['Overall Score'].blank?

        "#{sentences['Overall Score']} / #{sentences['Full Score']}"
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

      def generate_speaking_pronunciation_pdf(json_data, essay_grading, school_logo_url = nil, _submission_info = nil)
        Prawn::Document.new(page_size: 'A4', margin: [40, 40, 88, 40]) do |pdf|
          font_path = Rails.root.join('app/assets/fonts')

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
          draw_standard_report_footer(pdf)

          draw_standard_report_logo(pdf, school_logo_url)

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
        grading = EssayGrading.includes(:essay_assignment).find(grading.id) # 确保 essay_assignment 被加载
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
        effective_score_data = effective_score_sentences(essay_grading)
        effective_general_context = effective_general_context_data(essay_grading)
        effective_revised_essay = effective_revised_essay_text(essay_grading)

        json_data = {
          'topic' => assignment.topic,
          'account' => essay_grading.general_user.show_in_report_name,
          'assignment' => assignment.assignment,
          'rubric' => assignment.rubric['name'],
          'graph_image_url' => extract_task1_graph_image_url(assignment),
          'report_type' => report_type,
          'data' => { 'text' => effective_score_data.to_json }
        }

        if assignment.category == 'comprehension'
          json_data['comprehension'] = essay_grading.grading['comprehension']
          newsfeed = cached_news_feed_for(essay_grading)
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

          newsfeed = cached_news_feed_for(essay_grading)
          if newsfeed.present?
            json_data['title'] = extract_news_feed_title(newsfeed)
            json_data['article'] = extract_news_feed_body(newsfeed)
          end

          json_data['article'] ||= assignment.meta['listening_transcript'].presence ||
                                   sanitize_report_transcript(assignment.meta['listening_ssml_transcript'])
        elsif assignment.category.include?('essay') || assignment.category == 'speaking_conversation'
          json_data.merge!(essay_grading.grading)
          json_data['data'] = { 'text' => effective_score_data.to_json }

          if effective_general_context.present?
            json_data['general_context'] = effective_general_context['Feedback'] if effective_general_context['Feedback'].present?
            if effective_general_context['studentFeedback'].present?
              json_data['overall_comment'] = effective_general_context['studentFeedback']['overall']
              json_data['detailedFeedback'] = effective_general_context['studentFeedback']['detailedFeedback']
              if effective_general_context['studentFeedback']['sections'].present?
                json_data['general_context_sections'] = effective_general_context['studentFeedback']['sections']
              end
            end
          end

          json_data['revised_essay'] = effective_revised_essay if effective_revised_essay.present?
        end

        json_data
      end

      def normalized_report_type
        params[:report_type] == 'simplified' ? 'simplified' : 'full'
      end

      def draw_standard_report_logo(pdf, school_logo_url, width: 50, move_down: 20)
        if school_logo_url.present?
          begin
            pdf.image cached_remote_image_io(school_logo_url), at: [0, pdf.cursor], width: width
            pdf.move_down move_down
          rescue StandardError => e
            Rails.logger.error("Error loading school logo: #{e.message}")
          end
        else
          pdf.move_down move_down
        end
      end

      def cached_remote_image_io(url)
        StringIO.new(cached_remote_asset_bytes(url))
      end

      def cached_remote_asset_bytes(url)
        @remote_asset_bytes_cache ||= {}
        @remote_asset_bytes_cache[url] ||= URI.open(url, &:read)
      end

      def cached_news_feed_for(essay_grading)
        @news_feed_cache ||= {}
        key = [
          essay_grading.essay_assignment_id,
          essay_grading.essay_assignment.newsfeed_id,
          essay_grading.essay_assignment.level,
          essay_grading.newsfeed_id
        ].compact.join(':')
        @news_feed_cache[key] ||= essay_grading.get_news_feed
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

      def listening_answer_correct_for_report?(question)
        accepted_answers = Array(question['accepted_answers']).presence || [question['answer']]
        user_answer = normalized_report_answer(question['user_answer'])
        accepted_answers.any? { |answer| normalized_report_answer(answer) == user_answer }
      end

      def normalized_report_answer(value)
        value.to_s.strip.downcase.gsub(/\s+/, ' ')
      end

      def sanitize_report_transcript(value)
        text = value.to_s
        return nil if text.blank?

        stripped = text.gsub(/<[^>]+>/, ' ').gsub(/\s+/, ' ').strip
        stripped.presence
      end

      def teacher_review_params
        permitted = params.require(:teacher_review).permit(
          general_context: [
            :Feedback,
            {
              studentFeedback: [
                :overall,
                :detailedFeedback,
                {
                  sections: [
                    :content,
                    :organisation,
                    :oneStrength,
                    :oneKeyAreaForImprovement,
                    :logicAndCoherence
                  ]
                }
              ]
            }
          ],
          revised_essay: [:text],
          grammar: [
            {
              sentences: [
                :sentence_id,
                :position,
                :sentence_text,
                {
                  errors: [
                    :error_id,
                    :category,
                    :selected_text,
                    :start_index,
                    :end_index,
                    :correction,
                    :explanation
                  ]
                }
              ]
            }
          ]
        )

        raw_score_data = params.dig(:teacher_review, :score, :data)
        if raw_score_data.present?
          normalized_score_data = normalize_teacher_review_score_data(raw_score_data)
          permitted[:score] = { data: normalized_score_data } if normalized_score_data.present?
        end

        permitted
      end

      def teacher_can_edit_review?(essay_grading)
        return false unless current_general_user&.aienglish_role == 'teacher'

        assignment_owner_id = essay_grading.essay_assignment&.general_user_id
        return true if assignment_owner_id.blank?

        assignment_owner_id == current_general_user.id
      end

      def build_teacher_review_payload(payload)
        result = {}

        if payload['score'].present?
          score_data = payload.dig('score', 'data')
          result['score'] = {
            'data' => score_data.is_a?(Hash) ? score_data.deep_dup : {}
          }
        end

        if payload['general_context'].present?
          general_context = payload['general_context'].deep_dup
          if general_context['Feedback'].present?
            result['general_context'] = {
              'Feedback' => general_context['Feedback'].to_s
            }
          else
            student_feedback = general_context['studentFeedback'].is_a?(Hash) ? general_context['studentFeedback'].deep_dup : {}
            sections = student_feedback['sections'].is_a?(Hash) ? student_feedback['sections'].deep_dup : {}
            student_feedback['sections'] = sections
            student_feedback['detailedFeedback'] = build_general_context_detailed_feedback(student_feedback) if student_feedback['detailedFeedback'].blank?
            result['general_context'] = {
              'studentFeedback' => student_feedback
            }
          end
        end

        if payload['revised_essay'].present?
          result['revised_essay'] = {
            'text' => payload.dig('revised_essay', 'text').to_s
          }
        end

        if payload['grammar'].present?
          sentences = payload.dig('grammar', 'sentences')
          result['grammar'] = {
            'sentences' => Array(sentences).filter_map.with_index(1) do |sentence, sentence_index|
              next unless sentence.is_a?(Hash)

              {
                'sentence_id' => sentence['sentence_id'].presence || "sentence_#{sentence_index}",
                'position' => sentence['position'].presence || sentence_index,
                'sentence_text' => sentence['sentence_text'].to_s,
                'errors' => Array(sentence['errors']).filter_map.with_index(1) do |error, error_index|
                  next unless error.is_a?(Hash)

                  {
                    'error_id' => error['error_id'].presence || "sentence_#{sentence_index}_error_#{error_index}",
                    'category' => error['category'].to_s,
                    'selected_text' => error['selected_text'].to_s,
                    'start_index' => error['start_index'].nil? ? nil : error['start_index'].to_i,
                    'end_index' => error['end_index'].nil? ? nil : error['end_index'].to_i,
                    'correction' => error['correction'].to_s,
                    'explanation' => error['explanation'].to_s
                  }
                end
              }
            end
          }
        end

        result
      end

      def build_teacher_review_history_entry(review_hash)
        history_entry = review_hash.deep_dup
        history_entry['version_id'] ||= SecureRandom.uuid
        history_entry['saved_at'] = Time.current.as_json
        history_entry['saved_by'] = {
          'id' => current_general_user.id,
          'email' => current_general_user.email,
          'nickname' => current_general_user.nickname
        }
        history_entry
      end

      def normalize_teacher_review_score_data(raw_score_data)
        score_hash =
          case raw_score_data
          when ActionController::Parameters
            raw_score_data.to_unsafe_h
          when Hash
            raw_score_data.deep_dup
          else
            {}
          end

        allowed_root_keys = ['Overall Score', 'Full Score']
        normalized = score_hash.slice(*allowed_root_keys).transform_values { |value| value.to_s }

        score_hash.each do |key, value|
          next unless key.to_s.start_with?('Criterion')
          next unless value.is_a?(Hash) || value.is_a?(ActionController::Parameters)

          criterion_hash =
            case value
            when ActionController::Parameters
              value.to_unsafe_h
            else
              value.deep_dup
            end

          normalized[key] = criterion_hash.each_with_object({}) do |(criterion_key, criterion_value), result|
            next unless criterion_value.is_a?(String) || criterion_value.is_a?(Numeric)

            result[criterion_key.to_s] = criterion_value.to_s
          end
        end

        normalized
      end

      def build_general_context_detailed_feedback(student_feedback)
        overall = student_feedback['overall'].to_s.strip
        sections = student_feedback['sections'].is_a?(Hash) ? student_feedback['sections'] : {}
        section_labels = {
          'content' => 'Content',
          'organisation' => 'Organisation',
          'oneStrength' => 'One Strength',
          'oneKeyAreaForImprovement' => 'One Key Area for Improvement',
          'logicAndCoherence' => 'Logic & Coherence'
        }

        parts = []
        parts << overall if overall.present?
        section_labels.each do |key, label|
          value = sections[key].to_s.strip
          next if value.blank?

          parts << "#{label}\n#{value}"
        end
        parts.join("\n\n")
      end

      def extract_scores_from_sentences(grading_json)
        grading_json.each_with_object({}) do |(key, value), result|
          next unless key.to_s.start_with?('Criterion') && value.is_a?(Hash)

          value.each do |criterion_key, criterion_value|
            result[criterion_key] = criterion_value unless ['Full Score', 'explanation'].include?(criterion_key)
          end
        end
      end

      def effective_score_sentences(essay_grading)
        teacher_review_score = essay_grading.teacher_review_hash.dig('score', 'data')
        return teacher_review_score if teacher_review_score.is_a?(Hash) && teacher_review_score.present?

        JSON.parse(essay_grading.grading.dig('data', 'text').to_s)
      rescue StandardError
        {}
      end

      def effective_grammar_sentences(essay_grading, fallback_sentences = {})
        teacher_review_sentences = essay_grading.teacher_review_hash.dig('grammar', 'sentences')
        if teacher_review_sentences.is_a?(Array) && teacher_review_sentences.present?
          return teacher_review_sentences.each_with_index.each_with_object({}) do |(sentence, index), result|
            next unless sentence.is_a?(Hash)

            errors = Array(sentence['errors']).filter_map.with_index(1) do |error, error_index|
              next unless error.is_a?(Hash)

              selected_text = error['selected_text'].to_s
              correction = error['correction'].to_s

              [
                "error#{error_index}",
                {
                  'word' => selected_text,
                  'corr' => correction.present? ? "#{selected_text} -> #{correction}" : selected_text,
                  'category' => error['category'].to_s,
                  'explanation' => error['explanation'].to_s
                }
              ]
            end.to_h

            result["Sentence #{index + 1}"] = {
              'sentence' => sentence['sentence_text'].to_s,
              'errors' => errors
            }
          end
        end

        fallback_sentences.is_a?(Hash) ? fallback_sentences : {}
      end

      def effective_general_context_data(essay_grading)
        teacher_review_general_context = essay_grading.teacher_review_hash['general_context']
        return teacher_review_general_context if teacher_review_general_context.is_a?(Hash) && teacher_review_general_context.present?

        raw_general_context_text = essay_grading.general_context.dig('data', 'text').to_s
        return nil if raw_general_context_text.blank?

        JSON.parse(raw_general_context_text)
      rescue StandardError
        { 'Feedback' => raw_general_context_text.presence }.compact
      end

      def effective_revised_essay_text(essay_grading)
        teacher_review_text = essay_grading.teacher_review_hash.dig('revised_essay', 'text').to_s
        return teacher_review_text if teacher_review_text.present?

        revised_essay_data = essay_grading.revised_essay['data']
        return nil unless revised_essay_data.present?

        revised_essay_data['text'].to_s.presence || revised_essay_data['answer'].to_s.presence
      end

      # 準備提交資訊（優先使用submission的班級資訊）
      def prepare_submission_info(essay_grading)
        user = essay_grading.general_user

        # 優先使用submission信息（如果存在）
        class_name = essay_grading.submission_class_name.presence || user.banbie
        class_number = essay_grading.submission_class_number.presence || user.class_no

        "#{user.email} (#{user.nickname}, #{class_name}, #{class_number})"
      end
    end
  end
end
