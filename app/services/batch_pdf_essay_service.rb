# frozen_string_literal: true

require 'pdf-reader'
require 'open-uri'

class BatchPdfEssayService
  # 结果结构
  Result = Struct.new(:success?, :processed_count, :errors, :successful_gradings, :not_found_emails, keyword_init: true)

  def initialize(essay_assignment_id, teacher_user_id)
    @essay_assignment_id = essay_assignment_id
    @teacher_user_id = teacher_user_id
    @essay_assignment = EssayAssignment.find(essay_assignment_id)
    @teacher = GeneralUser.find(teacher_user_id)
    @errors = []
    @successful_gradings = []
    @not_found_emails = []
    @processed_count = 0
  end

  # 主要处理方法
  def process_pdfs(pdf_files)
    return Result.new(success?: false, error: 'No PDF files provided') if pdf_files.blank?

    pdf_files.each do |pdf_file|
      process_single_pdf(pdf_file)
    end

    Result.new(
      success?: @errors.empty?,
      processed_count: @processed_count,
      errors: @errors,
      successful_gradings: @successful_gradings,
      not_found_emails: @not_found_emails
    )
  rescue StandardError => e
    Rails.logger.error("[BatchPdfEssayService] Unexpected error: #{e.message}\n#{e.backtrace.join("\n")}")
    @errors << "Service error: #{e.message}"
    Result.new(
      success?: false, 
      processed_count: @processed_count, 
      errors: @errors, 
      successful_gradings: @successful_gradings,
      not_found_emails: @not_found_emails
    )
  end

  # 异步处理单个PDF文件（用于后台任务）
  def process_single_pdf_async(pdf_file)
    process_single_pdf(pdf_file)
    
    Result.new(
      success?: @errors.empty?,
      processed_count: @processed_count,
      errors: @errors,
      successful_gradings: @successful_gradings,
      not_found_emails: @not_found_emails
    )
  end

  private

  def process_single_pdf(pdf_file)
    # 从文件名提取学生email（去掉.pdf扩展名）
    student_email = extract_email_from_filename(pdf_file.original_filename)
    
    # 查找学生用户
    student = find_student_by_email(student_email)
    
    if student.nil?
      @not_found_emails << student_email
      Rails.logger.warn("[BatchPdfEssayService] Student not found for email: #{student_email}")
      return
    end

    # 检查学生是否已经有这个作业的评分记录
    # if student_has_existing_grading?(student.id)
    #   @errors << "Student #{student_email} already has a grading for this assignment"
    #   return
    # end

    # 提取PDF内容
    # essay_content = extract_pdf_content(pdf_file)
    # puts "essay_content: #{essay_content}"
    # essay_content = "test pdf content" 
    storage_url = AzureService.upload(pdf_file) if pdf_file.present?
    ocrRes = RestClient.post "#{ENV['DOCAI_ALPHA_URL']}/alpha/ocr", { document_url: storage_url }
    essay_content = JSON.parse(ocrRes)['result']
    # puts "essay_content: #{essay_content}" 

    # @errors << "Could not extract content from PDF for student: #{student_email}"
    # return

    if essay_content.blank?
      @errors << "Could not extract content from PDF for student: #{student_email}"
      return
    end

    # 创建EssayGrading记录
    grading = create_essay_grading(student, essay_content, pdf_file)
    
    if grading&.persisted?
      @successful_gradings << grading
      @processed_count += 1
      Rails.logger.info("[BatchPdfEssayService] Successfully created grading for student: #{student_email}")
    else
      @errors << "Failed to create grading for student: #{student_email}"
    end

  rescue StandardError => e
    Rails.logger.error("[BatchPdfEssayService] Error processing PDF #{pdf_file.original_filename}: #{e.message}")
    @errors << "Error processing #{pdf_file.original_filename}: #{e.message}"
  end

  def extract_email_from_filename(filename)
    # 移除.pdf扩展名，文件名应该是学生email
    filename.gsub(/\.pdf$/i, '').strip
  end

  def find_student_by_email(email)
    GeneralUser.find_by(email: email)
  end

  def student_has_existing_grading?(student_id)
    @essay_assignment.essay_gradings.exists?(general_user_id: student_id)
  end

  def get_file_stream(pdf_file)
    if pdf_file.is_a?(ActionDispatch::Http::UploadedFile)
      # 未保存的上传文件，直接使用其 temp file
      pdf_file.tempfile
    elsif @pdf_file.is_a?(ActiveStorage::Attached::One) || pdf_file.is_a?(ActiveStorage::Attachment)
      # 已保存的 Active Storage 附件
      pdf_file.open { |file| file }
    else
      Rails.logger.error("[PdfContentExtractor] 不支持的文件类型: #{pdf_file.class}")
      nil
    end
  end

  def extract_pdf_content(pdf_file)
    content = nil
    file_stream = get_file_stream(pdf_file)
    return nil unless file_stream

    begin
      file_stream.rewind
      reader = PDF::Reader.new(file_stream)
      text = reader.pages.map do |page|
        begin
          page.text.strip
        rescue StandardError => e
          Rails.logger.warn("[PdfContentExtractor] 页面文本提取失败: #{e.message}")
          ''
        end
      end.join("\n").strip

      content = text.presence
    rescue PDF::Reader::MalformedPDFError => e
      Rails.logger.error("[PdfContentExtractor] PDF 格式错误: #{e.message}")
      nil
    rescue StandardError => e
      Rails.logger.error("[PdfContentExtractor] PDF-Reader 提取失败: #{e.message}")
      nil
    ensure
      file_stream.close if file_stream && !file_stream.closed?
    end
    content
  end

  def extract_content_with_azure_ocr(pdf_file)
    # 这里可以调用Azure OCR服务
    # 对于Active Storage文件，我们需要先下载到临时文件或直接使用文件流
    begin
      # 使用Active Storage的download方法获取文件内容
      temp_file = pdf_file.download
      
      # 调用Azure OCR服务（需要完善AzureOcrService）
      # 这里暂时返回nil，后续可以完善Azure OCR集成
      Rails.logger.warn("[BatchPdfEssayService] Azure OCR not fully implemented yet")
      
      # 清理临时文件
      temp_file.close
      temp_file.unlink
      
      nil
    rescue StandardError => e
      Rails.logger.error("[BatchPdfEssayService] Azure OCR processing failed: #{e.message}")
      nil
    end
  end

  def create_essay_grading(student, essay_content, pdf_file)
    grading = @essay_assignment.essay_gradings.new(
      general_user: student,
      essay: essay_content,
      topic: @essay_assignment.topic,
      status: 'pending'
    )

    # 设置grading和general_context的app_key
    if @essay_assignment.rubric.present? && @essay_assignment.rubric['app_key'].present?
      grading.grading ||= {}
      grading.grading['app_key'] = @essay_assignment.rubric['app_key']['grading']
      grading.general_context ||= {}
      grading.general_context['app_key'] = @essay_assignment.rubric['app_key']['general_context']
    end

    # 设置学校相关信息（如果学生有关联的学校）
    if student.school.present?
      grading.submission_school = student.school
      # 如果有当前学年，也设置
      current_enrollment = student.student_enrollments.joins(:school_academic_year)
                                 .where(school_academic_years: { is_current: true })
                                 .first
      grading.submission_academic_year = current_enrollment&.school_academic_year
    end

    # 设置提交的班级信息
    grading.submission_class_name = student.banbie
    grading.submission_class_number = student.class_no

    # 使用Active Storage附加PDF文件
    begin
      grading.file.attach(
        io: pdf_file.open,
        filename: pdf_file.original_filename,
        content_type: pdf_file.content_type
      )
    rescue StandardError => e
      Rails.logger.error("[BatchPdfEssayService] Failed to attach PDF file: #{e.message}")
      @errors << "Failed to attach PDF file for student: #{student.email}"
      return nil
    end

    # 保存记录
    if grading.save
      # 记录提交事件
      track_submission_event(grading)
      grading
    else
      Rails.logger.error("[BatchPdfEssayService] Failed to save grading: #{grading.errors.full_messages}")
      nil
    end
  end

  def track_submission_event(grading)
    # 使用Ahoy跟踪作业提交事件
    begin
      # 确保Ahoy tracker与提交作业的用户正确关联
      ahoy = Ahoy::Tracker.new
      ahoy.authenticate(grading.general_user)
      ahoy.track 'Assignment Submitted via Batch PDF Upload',
                 { 
                   essay_grading_id: grading.id, 
                   essay_assignment_id: @essay_assignment.id,
                   uploaded_by_teacher: @teacher.id,
                   submission_method: 'batch_pdf_upload'
                 }
    rescue StandardError => e
      Rails.logger.error("[BatchPdfEssayService] Failed to track submission event: #{e.message}")
    end
  end
end
