# frozen_string_literal: true

module Api
  module V1
    class SupplementPracticeRecordsController < ApiController
      before_action :authenticate_general_user!, except: [:download_report]
      before_action :set_essay_grading, only: [:show_questions, :create_draft, :submit]
      before_action :set_record, only: [:show, :show_record, :download_report]
    #   before_action :check_record_ownership, only: [:show, :show_record, :download_report]

      # GET /api/v1/essay_gradings/:essay_grading_id/supplement_practice
      # 获取补充练习题目（学生端）
      def show_questions
        # 检查是否有 supplement_practice 数据
        unless @essay_grading.grading['supplement_practice'].present?
          return render json: { success: false, error: 'Supplement practice not found' }, status: :not_found
        end

        parser = SupplementPracticeParserService.new(@essay_grading)
        questions_data = parser.parse_for_student

        unless questions_data
          return render json: { success: false, error: 'Failed to parse supplement practice data' }, status: :unprocessable_entity
        end

        # 检查是否有已保存的记录
        existing_record = SupplementPracticeRecord.existing_record_for(@essay_grading.id, current_general_user.id)
        
        response_data = {
          essay_grading_id: @essay_grading.id,
          quizTitle: questions_data['quizTitle'],
          sections: questions_data['sections'],
          has_existing_record: existing_record.present?,
          existing_record: existing_record ? {
            id: existing_record.id,
            status: existing_record.status,
            answers: existing_record.answers,
            score: existing_record.score,
            full_score: existing_record.full_score,
            using_time: existing_record.using_time
          } : nil
        }

        render json: { success: true, data: response_data }, status: :ok
      rescue OldDataFormatError => e
        Rails.logger.error("[SupplementPracticeRecordsController] Old data format detected: #{e.message}")
        render json: { success: false, code: e.code, message: e.message }, status: :ok
      rescue StandardError => e
        Rails.logger.error("[SupplementPracticeRecordsController] Error in show_questions: #{e.message}")
        Rails.logger.error(e.backtrace.first(5).join("\n"))
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      # POST /api/v1/essay_gradings/:essay_grading_id/supplement_practice/draft
      # 保存草稿
      def create_draft
        parser = SupplementPracticeParserService.new(@essay_grading)
        questions_data = parser.parse

        unless questions_data
          return render json: { success: false, error: 'Failed to parse supplement practice data' }, status: :unprocessable_entity
        end

        # 查找或创建草稿记录
        record = SupplementPracticeRecord.find_or_initialize_by(
          essay_grading_id: @essay_grading.id,
          general_user_id: current_general_user.id,
          status: :draft
        )

        record.answers = draft_params[:answers]
        record.questions_data = questions_data
        record.using_time = draft_params[:using_time] || 0
        record.started_at ||= Time.current
        record.essay_assignment_id = @essay_grading.essay_assignment_id

        if record.save
          render json: {
            success: true,
            data: {
              id: record.id,
              status: record.status,
              saved_at: record.updated_at
            }
          }, status: :ok
        else
          render json: { success: false, errors: record.errors.full_messages }, status: :unprocessable_entity
        end
      rescue OldDataFormatError => e
        Rails.logger.error("[SupplementPracticeRecordsController] Old data format detected in create_draft: #{e.message}")
        render json: { success: false, code: e.code, message: e.message }, status: :ok
      rescue StandardError => e
        Rails.logger.error("[SupplementPracticeRecordsController] Error in create_draft: #{e.message}")
        Rails.logger.error(e.backtrace.first(5).join("\n"))
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      # POST /api/v1/essay_gradings/:essay_grading_id/supplement_practice/submit
      # 提交练习
      def submit
        # 检查是否已经提交过
        existing_submitted = SupplementPracticeRecord.find_by(
          essay_grading_id: @essay_grading.id,
          general_user_id: current_general_user.id,
          status: :submitted
        )

        if existing_submitted
          return render json: { success: false, error: '该作业的练习已经提交，不能重复提交' }, status: :unprocessable_entity
        end

        parser = SupplementPracticeParserService.new(@essay_grading)
        questions_data = parser.parse

        unless questions_data
          return render json: { success: false, error: 'Failed to parse supplement practice data' }, status: :unprocessable_entity
        end

        # 查找草稿记录或创建新记录
        record = SupplementPracticeRecord.find_or_initialize_by(
          essay_grading_id: @essay_grading.id,
          general_user_id: current_general_user.id,
          status: :draft
        )

        record.answers = submit_params[:answers]
        record.questions_data = questions_data
        record.using_time = submit_params[:using_time] || 0
        record.started_at ||= Time.current
        record.submitted_at = Time.current
        record.status = :submitted
        record.essay_assignment_id = @essay_grading.essay_assignment_id

        # 计算分数
        scoring_result = SupplementPracticeScoringService.new(record).calculate
        record.score = scoring_result[:score]
        record.full_score = scoring_result[:full_score]
        record.questions_count = scoring_result[:questions_count]

        if record.save
          render json: {
            success: true,
            data: {
              id: record.id,
              score: record.score,
              full_score: record.full_score,
              questions_count: record.questions_count,
              correct_count: scoring_result[:correct_count],
              incorrect_count: scoring_result[:incorrect_count],
              submitted_at: record.submitted_at
            }
          }, status: :ok
        else
          render json: { success: false, errors: record.errors.full_messages }, status: :unprocessable_entity
        end
      rescue OldDataFormatError => e
        Rails.logger.error("[SupplementPracticeRecordsController] Old data format detected in submit: #{e.message}")
        render json: { success: false, code: e.code, message: e.message }, status: :ok
      rescue StandardError => e
        Rails.logger.error("[SupplementPracticeRecordsController] Error in submit: #{e.message}")
        Rails.logger.error(e.backtrace.first(5).join("\n"))
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      # GET /api/v1/supplement_practice_records/my_records
      # 获取我的所有练习记录（学生端）
      def my_records
        # 获取当前用户的所有练习记录
        @records = SupplementPracticeRecord
                   .includes(:essay_grading, :essay_assignment)
                   .where(general_user_id: current_general_user.id)
                   .order('submitted_at desc, created_at desc')

        # 分页
        @records = Kaminari.paginate_array(@records.to_a).page(params[:page]).per(params[:count] || 10)

        render json: {
          success: true,
          supplement_practice_records: @records.map do |record|
            {
              id: record.id,
              essay_grading_id: record.essay_grading_id,
              essay_assignment_id: record.essay_assignment_id,
              essay_grading: {
                id: record.essay_grading.id,
                topic: record.essay_grading.topic,
                assignment: record.essay_grading.essay_assignment&.assignment
              },
              status: record.status,
              score: record.score,
              full_score: record.full_score,
              questions_count: record.questions_count,
              using_time: record.using_time,
              started_at: record.started_at,
              submitted_at: record.submitted_at,
              created_at: record.created_at,
              updated_at: record.updated_at,
              quizTitle: record.questions_data['quizTitle']
            }
          end,
          meta: pagination_meta(@records)
        }, status: :ok
      rescue StandardError => e
        Rails.logger.error("[SupplementPracticeRecordsController] Error in my_records: #{e.message}")
        Rails.logger.error(e.backtrace.first(5).join("\n"))
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      # GET /api/v1/supplement_practice_records/:id
      # 查看自己的练习记录
      def show
        show_record
      end

      def show_record
        # 构建响应数据，包含题目、答案和对错情况
        response_data = build_record_response(@record)
        
        render json: { success: true, data: response_data }, status: :ok
      rescue StandardError => e
        Rails.logger.error("[SupplementPracticeRecordsController] Error in show_record: #{e.message}")
        Rails.logger.error(e.backtrace.first(5).join("\n"))
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      # GET /api/v1/supplement_practice_records/:id/download_report
      # 下载 PDF 报告
      def download_report
        unless @record.submitted?
          return render json: { success: false, error: '只能下载已提交的练习报告' }, status: :unprocessable_entity
        end

        pdf = generate_supplement_practice_pdf(@record)
        filename = "#{@record.general_user.nickname}_supplement_practice_#{@record.id}.pdf"
        send_data pdf.render, filename: filename, type: 'application/pdf', disposition: 'inline'
      rescue StandardError => e
        Rails.logger.error("[SupplementPracticeRecordsController] Error in download_report: #{e.message}")
        Rails.logger.error(e.backtrace.first(10).join("\n"))
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      # GET /api/v1/essay_assignments/:essay_assignment_id/supplement_practice_records
      # 教师端：通过作业ID查看该作业的所有练习记录（列表视图）
      def by_assignment_id
        @essay_assignment = EssayAssignment.includes(:assigned_students).find(params[:essay_assignment_id])
        
        # 权限检查：只有教师可以查看
        unless current_general_user.aienglish_role == 'teacher'
          return render json: { success: false, error: 'Unauthorized' }, status: :forbidden
        end

        status_filter = params[:status] || 'submitted'
        
        # 使用数据库分页而不是内存分页，提高性能
        records_query = SupplementPracticeRecord
                        .includes(:general_user, :essay_grading)
                        .where(essay_assignment_id: @essay_assignment.id)
                        .where(status: status_filter)
                        .order(submitted_at: :desc)

        # 使用 Kaminari 的数据库分页
        records = records_query.page(params[:page] || 1).per(params[:per_page] || 100)

        # 构建响应数据
        records_data = records.map do |record|
          {
            id: record.id,
            general_user: {
              id: record.general_user.id,
              nickname: record.general_user.nickname,
              email: record.general_user.email
            },
            essay_grading: {
              id: record.essay_grading.id,
              topic: record.essay_grading.topic
            },
            status: record.status,
            score: record.score,
            full_score: record.full_score,
            using_time: record.using_time,
            submitted_at: record.submitted_at
          }
        end

        # 优化统计信息查询：使用数据库聚合查询，避免加载所有记录到内存
        base_query = SupplementPracticeRecord.where(essay_assignment_id: @essay_assignment.id)
        
        # 使用单个查询获取所有状态的计数（不包含其他字段，避免 GROUP BY 错误）
        status_counts = base_query.group(:status).count
        total_submitted = status_counts['submitted'] || status_counts[1] || 0
        total_draft = status_counts['draft'] || status_counts[0] || 0
        
        # 只对 submitted 记录计算平均值（使用 Rails 的 calculate 方法，避免 GROUP BY 错误）
        submitted_query = base_query.where(status: :submitted)
        
        # 使用 calculate 方法进行聚合计算，这是 Rails 推荐的方式
        average_score = submitted_query.average(:score)&.to_f&.round(2) || 0
        average_using_time = submitted_query.average(:using_time)&.to_f&.round(0) || 0
        
        # 获取已分配学生数量（已通过 includes 预加载，避免额外查询）
        # assigned_students_count = @essay_assignment.assigned_students.size
        # completion_rate = if assigned_students_count > 0
        #                     (total_submitted.to_f / assigned_students_count * 100).round(2)
        #                   else
        #                     0
        #                   end
        
        statistics = {
          total_submitted: total_submitted,
          total_draft: total_draft,
          average_score: average_score,
          average_using_time: average_using_time,
          completion_rate: 0#completion_rate
        }

        render json: {
          success: true,
          data: {
            records: records_data,
            statistics: statistics,
            meta: pagination_meta(records)
          }
        }, status: :ok
      rescue StandardError => e
        Rails.logger.error("[SupplementPracticeRecordsController] Error in by_assignment_id: #{e.message}")
        Rails.logger.error(e.backtrace.first(5).join("\n"))
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      # GET /api/v1/essay_gradings/:essay_grading_id/supplement_practice_records
      # 教师端：查看某个作业的所有练习记录（列表视图）
      def index
        @essay_grading = EssayGrading.find(params[:essay_grading_id])
        
        # 权限检查：只有教师可以查看
        unless current_general_user.aienglish_role == 'teacher'
          return render json: { success: false, error: 'Unauthorized' }, status: :forbidden
        end

        status_filter = params[:status] || 'submitted'
        records = @essay_grading.supplement_practice_records
                                .includes(:general_user)
                                .where(status: status_filter)
                                .order(submitted_at: :desc)

        records = Kaminari.paginate_array(records.to_a).page(params[:page] || 1).per(params[:per_page] || 20)

        records_data = records.map do |record|
          {
            id: record.id,
            general_user: {
              id: record.general_user.id,
              nickname: record.general_user.nickname,
              email: record.general_user.email
            },
            status: record.status,
            score: record.score,
            full_score: record.full_score,
            using_time: record.using_time,
            submitted_at: record.submitted_at
          }
        end

        # 计算统计信息
        all_submitted = @essay_grading.supplement_practice_records.submitted
        all_drafts = @essay_grading.supplement_practice_records.draft
        
        statistics = {
          total_submitted: all_submitted.count,
          total_draft: all_drafts.count,
          average_score: all_submitted.any? ? (all_submitted.sum(:score) / all_submitted.count.to_f).round(2) : 0,
          average_using_time: all_submitted.any? ? (all_submitted.sum(:using_time) / all_submitted.count.to_f).round(0) : 0,
          completion_rate: @essay_grading.essay_assignment ? 
            (all_submitted.count.to_f / @essay_grading.essay_assignment.assigned_students.count * 100).round(2) : 0
        }

        render json: {
          success: true,
          data: {
            records: records_data,
            statistics: statistics,
            meta: pagination_meta(records)
          }
        }, status: :ok
      rescue StandardError => e
        Rails.logger.error("[SupplementPracticeRecordsController] Error in index: #{e.message}")
        Rails.logger.error(e.backtrace.first(5).join("\n"))
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      # GET /api/v1/essay_gradings/:essay_grading_id/supplement_practice_records/by_assignment
      # 教师端：作业关联视图
      def by_assignment
        @essay_grading = EssayGrading.find(params[:essay_grading_id])
        
        # 权限检查：只有教师可以查看
        unless current_general_user.aienglish_role == 'teacher'
          return render json: { success: false, error: 'Unauthorized' }, status: :forbidden
        end

        # 获取所有提交了该作业的学生
        essay_gradings = EssayGrading.where(essay_assignment_id: @essay_grading.essay_assignment_id)
                                    .includes(:general_user, :supplement_practice_records)

        students_data = essay_gradings.map do |eg|
          practice_record = eg.supplement_practice_records.submitted.first
          
          {
            general_user: {
              id: eg.general_user.id,
              nickname: eg.general_user.nickname,
              email: eg.general_user.email
            },
            essay_grading: {
              id: eg.id,
              submitted_at: eg.created_at,
              status: eg.status
            },
            supplement_practice_record: practice_record ? {
              id: practice_record.id,
              status: practice_record.status,
              score: practice_record.score,
              full_score: practice_record.full_score,
              submitted_at: practice_record.submitted_at
            } : nil
          }
        end

        # 计算统计信息
        submitted_count = students_data.count { |s| s[:supplement_practice_record].present? }
        not_submitted_count = students_data.count - submitted_count
        submitted_records = essay_gradings.flat_map(&:supplement_practice_records).select(&:submitted?)
        
        statistics = {
          total_students: students_data.count,
          submitted_count: submitted_count,
          not_submitted_count: not_submitted_count,
          average_score: submitted_records.any? ? (submitted_records.sum(&:score) / submitted_records.count.to_f).round(2) : 0,
          submission_rate: students_data.count > 0 ? (submitted_count.to_f / students_data.count * 100).round(2) : 0
        }

        render json: {
          success: true,
          data: {
            students: students_data,
            statistics: statistics
          }
        }, status: :ok
      rescue StandardError => e
        Rails.logger.error("[SupplementPracticeRecordsController] Error in by_assignment: #{e.message}")
        Rails.logger.error(e.backtrace.first(5).join("\n"))
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      private

      def set_essay_grading
        @essay_grading = EssayGrading.find(params[:id])
      end

      def set_record
        @record = SupplementPracticeRecord.find(params[:id])
      end

      def check_record_ownership
        unless @record.general_user_id == current_general_user.id || current_general_user.aienglish_role == 'teacher'
          render json: { success: false, error: 'Unauthorized' }, status: :forbidden
        end
      end

      def draft_params
        params.require(:answers)
        params.permit(
          :using_time,
          answers: {
            sections: [
              :topic,
              :type,
              {
                questions: [
                  :question,
                  :statement,
                  :id,
                  :user_answer
                ]
              }
            ]
          }
        )
      end

      def submit_params
        params.require(:answers)
        params.permit(
          :using_time,
          answers: {
            sections: [
              :topic,
              :type,
              {
                questions: [
                  :question,
                  :statement,
                  :id,
                  :user_answer
                ]
              }
            ]
          }
        )
      end

      def build_record_response(record)
        questions_data = record.questions_data
        answers = record.answers
        
        # 构建包含对错情况的题目数据
        sections_with_results = questions_data['sections'].map do |section|
          answer_section = answers['sections']&.find { |s| s['topic'] == section['topic'] && s['type'] == section['type'] }
          
          questions_with_results = section['questions'].map do |question|
            user_answer_data = find_user_answer_for_question(answer_section, question, section['type'])
            is_correct = check_answer_for_question(question, user_answer_data, section['type'])
            
            question_result = question.dup
            question_result['user_answer'] = extract_user_answer_value(user_answer_data, section['type'])
            question_result['correct_answer'] = question['answer']
            question_result['is_correct'] = is_correct
            
            question_result.delete('answer') unless current_general_user.aienglish_role == 'teacher'
            question_result
          end
          
          section_result = section.dup
          section_result['questions'] = questions_with_results
          section_result
        end

        {
          id: record.id,
          essay_grading_id: record.essay_grading_id,
          essay_grading: {
            id: record.essay_grading.id,
            topic: record.essay_grading.topic,
            assignment: record.essay_grading.essay_assignment&.assignment
          },
          general_user: {
            id: record.general_user.id,
            nickname: record.general_user.nickname,
            email: record.general_user.email,
            class_name: record.general_user.banbie,
            class_no: record.general_user.class_no
          },
          status: record.status,
          score: record.score,
          full_score: record.full_score,
          questions_count: record.questions_count,
          correct_count: SupplementPracticeScoringService.new(record).calculate[:correct_count],
          incorrect_count: SupplementPracticeScoringService.new(record).calculate[:incorrect_count],
          using_time: record.using_time,
          started_at: record.started_at,
          submitted_at: record.submitted_at,
          quizTitle: questions_data['quizTitle'],
          sections: sections_with_results
        }
      end

      def find_user_answer_for_question(answer_section, question, section_type)
        return nil unless answer_section && answer_section['questions']

        case section_type
        when 'fill_in_the_blanks'
          answer_section['questions'].find { |q| q['id'] == question['id'] }
        when 'multiple_choice'
          answer_section['questions'].find { |q| q['question'] == question['question'] }
        when 'true_or_false'
          answer_section['questions'].find { |q| q['statement'] == question['statement'] }
        end
      end

      def check_answer_for_question(question, user_answer_data, section_type)
        return false unless user_answer_data

        correct_answer = question['answer']
        user_answer = extract_user_answer_value(user_answer_data, section_type)

        case section_type
        when 'fill_in_the_blanks'
          normalize_string(user_answer) == normalize_string(correct_answer)
        when 'multiple_choice'
          user_answer == correct_answer
        when 'true_or_false'
          normalize_boolean(user_answer) == normalize_boolean(correct_answer)
        else
          false
        end
      end

      def extract_user_answer_value(user_answer_data, section_type)
        user_answer_data['user_answer']
      end

      def normalize_string(str)
        return '' unless str.is_a?(String)
        str.strip.downcase
      end

      def normalize_boolean(value)
        case value
        when true, 'true', 'True', 'TRUE', 1, '1'
          true
        when false, 'false', 'False', 'FALSE', 0, '0'
          false
        else
          false
        end
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

      # 生成补充练习 PDF 报告
      def generate_supplement_practice_pdf(record)
        require 'prawn'
        require 'open-uri'

        essay_grading = record.essay_grading
        user = record.general_user
        questions_data = record.questions_data
        answers = record.answers

        # 只有 AI English 用戶才會有學校 logo
        school_logo_url = user.aienglish_user? ? user.school_logo_url(:small) : nil

        # 準備用戶顯示資訊（優先使用提交班級資訊）
        submission_info = prepare_submission_info(essay_grading)

        Prawn::Document.new(page_size: 'A4', margin: 40) do |pdf|
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

          # 處理學校 Logo
          if school_logo_url.present?
            begin
              logo_tempfile = URI.open(school_logo_url)
              pdf.image logo_tempfile, at: [0, pdf.cursor], width: 50
              pdf.move_down 20
            rescue StandardError => e
              Rails.logger.error("Error loading school logo: #{e.message}")
              pdf.move_down 20
            end
          else
            pdf.move_down 20
          end

          # 標題
          pdf.text 'Supplementary Practice Report', size: 20, style: :bold, align: :center
          pdf.stroke_color '444444'
          pdf.move_down 25

          # 作業信息
          pdf.text 'Assignment Information', size: 15, style: :bold
          pdf.stroke_color '444444'
          pdf.stroke_horizontal_rule
          pdf.move_down 12

          info_data = [
            ['Assignment:', essay_grading.essay_assignment&.assignment || 'N/A'],
            ['Topic:', essay_grading.topic || 'N/A'],
            ['Account:', user.show_in_report_name || 'N/A']
          ]

          info_data.each do |label, value|
            pdf.formatted_text [
              { text: label, styles: [:bold], size: 12 },
              { text: " #{value}", size: 12 }
            ]
            pdf.move_down 4
          end

          pdf.move_down 25

          # 分數概覽
          pdf.text 'Assessment Overview', size: 15, style: :bold
          pdf.stroke_horizontal_rule
          pdf.move_down 12

          pdf.formatted_text [
            { text: 'Overall Score: ', styles: [:bold], size: 14 },
            { text: "#{record.score} / #{record.full_score}", size: 14 }
          ]
          pdf.move_down 8

          completion_percentage = record.completion_percentage
          pdf.formatted_text [
            { text: 'Completion Rate: ', styles: [:bold], size: 12 },
            { text: "#{completion_percentage}%", size: 12 }
          ]
          pdf.move_down 8

          pdf.formatted_text [
            { text: 'Correct: ', styles: [:bold], size: 12 },
            { text: "#{record.score.to_i} questions", size: 12 },
            { text: ' | ', size: 12 },
            { text: 'Incorrect: ', styles: [:bold], size: 12 },
            { text: "#{(record.full_score - record.score).to_i} questions", size: 12 }
          ]

          pdf.move_down 25

          # 題目詳情（按 section 分組）
          pdf.text 'Questions & Answers', size: 15, style: :bold
          pdf.stroke_horizontal_rule
          pdf.move_down 15

          questions_data['sections']&.each_with_index do |section, section_index|
            # Section 標題
            pdf.fill_color '333333'
            pdf.text "#{section_index + 1}. #{section['topic']}", size: 14, style: :bold
            pdf.fill_color '000000'
            pdf.move_down 5

            # Section 說明
            if section['instructions'].present?
              pdf.text section['instructions'], size: 11, style: :italic
              pdf.move_down 8
            end

            # 題目列表
            section['questions']&.each_with_index do |question, question_index|
              global_question_index = calculate_global_question_index(questions_data, section_index, question_index)
              
              # 找到對應的用戶答案
              answer_section = answers['sections']&.find { |s| s['topic'] == section['topic'] && s['type'] == section['type'] }
              user_answer_data = find_user_answer_for_question(answer_section, question, section['type'])
              is_correct = check_answer_for_question(question, user_answer_data, section['type'])

              # 題號和題目內容
            #   pdf.text "Q#{global_question_index + 1}.", size: 12, style: :bold, inline_format: true
            #   pdf.move_down 3

              case section['type']
              when 'multiple_choice'
                # 題目文本
                pdf.text "Q#{global_question_index + 1}. #{question['question']}", size: 11
                pdf.move_down 5

                # 選項
                question['options']&.each_with_index do |option, option_index|
                  pdf.text "  #{option_index + 1}. #{option}", size: 10
                end
                pdf.move_down 5

                # 學生答案
                user_answer = user_answer_data ? user_answer_data['user_answer'] : 'Not answered'
                pdf.fill_color is_correct ? '008000' : 'FF0000'
                pdf.text "My Answer: #{user_answer}", size: 11, style: :bold
                pdf.fill_color '000000'
                pdf.move_down 3

                # 正確答案
                pdf.fill_color '008000'
                pdf.text "Correct Answer: #{question['answer']}", size: 11, style: :bold
                pdf.fill_color '000000'

              when 'true_or_false'
                # Statement
                pdf.text "Q#{global_question_index + 1}. #{question['statement']}", size: 11
                pdf.move_down 5

                # 學生答案
                user_answer = user_answer_data ? (user_answer_data['user_answer'] ? 'True' : 'False') : 'Not answered'
                pdf.fill_color is_correct ? '008000' : 'FF0000'
                pdf.text "My Answer: #{user_answer}", size: 11, style: :bold
                pdf.fill_color '000000'
                pdf.move_down 3

                # 正確答案
                correct_answer_text = question['answer'] ? 'True' : 'False'
                pdf.fill_color '008000'
                pdf.text "Correct Answer: #{correct_answer_text}", size: 11, style: :bold
                pdf.fill_color '000000'

              when 'fill_in_the_blanks'
                # 題目文本（將 [[blank_X]] 替換為下劃線）
                question_text = render_fill_in_the_blank_question(question)
                pdf.text "Q#{global_question_index + 1}. #{question_text}", size: 11
                pdf.move_down 5

                # 學生答案
                user_answer = user_answer_data ? user_answer_data['user_answer'] : 'Not answered'
                pdf.fill_color is_correct ? '008000' : 'FF0000'
                pdf.text "My Answer: #{user_answer}", size: 11, style: :bold
                pdf.fill_color '000000'
                pdf.move_down 3

                # 正確答案
                pdf.fill_color '008000'
                pdf.text "Correct Answer: #{question['answer']}", size: 11, style: :bold
                pdf.fill_color '000000'
              end

              pdf.move_down 12
            end

            # Section 之間的分隔
            pdf.move_down 10
            pdf.stroke_color 'CCCCCC'
            pdf.stroke_horizontal_rule
            pdf.move_down 15
          end

          # 最終結果
          pdf.move_down 10
          pdf.text 'Final Result', size: 15, style: :bold
          pdf.stroke_color '444444'
          pdf.stroke_horizontal_rule
          pdf.move_down 10

          pdf.formatted_text [
            { text: 'Overall Score: ', styles: [:bold], size: 14 },
            { text: "#{record.score} / #{record.full_score}", size: 14 }
          ]
          pdf.move_down 5

          pdf.formatted_text [
            { text: 'Completion Rate: ', styles: [:bold], size: 12 },
            { text: "#{completion_percentage}%", size: 12 }
          ]
          pdf.move_down 5

          if record.submitted_at.present?
            pdf.formatted_text [
              { text: 'Submitted At: ', styles: [:bold], size: 11 },
              { text: record.submitted_at.strftime('%Y-%m-%d %H:%M:%S'), size: 11 }
            ]
          end

          pdf.move_down 20
        end
      end

      def prepare_submission_info(essay_grading)
        user = essay_grading.general_user
        class_name = essay_grading.submission_class_name.presence || user.banbie
        class_number = essay_grading.submission_class_number.presence || user.class_no
        "#{user.email} (#{user.nickname}, #{class_name}, #{class_number})"
      end

      # 渲染填充題的 question，將 [[blank_X]] 替換為下劃線
      def render_fill_in_the_blank_question(question)
        return '' unless question['question']

        question_text = question['question']
        # 匹配 [[blank_X]] 格式，將所有匹配項替換為下劃線
        blank_regex = /\[\[(\w+)\]\]/
        question_text.gsub(blank_regex, '____')
      end

      # 計算全局題號（跨 section）
      def calculate_global_question_index(questions_data, section_index, question_index)
        index = 0
        questions_data['sections']&.each_with_index do |section, idx|
          if idx < section_index
            index += section['questions']&.count || 0
          elsif idx == section_index
            index += question_index
            break
          end
        end
        index
      end
    end
  end
end
