# frozen_string_literal: true

class BatchPdfEssayJob
  include Sidekiq::Job
  
  sidekiq_options queue: :pdf_processing, retry: 3

  def perform(essay_assignment_id, teacher_user_id, pdf_file_data)
    # 从Active Storage中获取PDF文件
    pdf_file = retrieve_pdf_file(pdf_file_data)
    return unless pdf_file

    # 处理单个PDF文件
    service = BatchPdfEssayService.new(essay_assignment_id, teacher_user_id)
    result = service.process_single_pdf_async(pdf_file)

    if result.success?
      Rails.logger.info("[BatchPdfEssayJob] Successfully processed PDF for assignment #{essay_assignment_id}")
    else
      Rails.logger.error("[BatchPdfEssayJob] Failed to process PDF for assignment #{essay_assignment_id}: #{result.error}")
    end

  rescue StandardError => e
    Rails.logger.error("[BatchPdfEssayJob] Error processing PDF for assignment #{essay_assignment_id}: #{e.message}\n#{e.backtrace.join("\n")}")
    raise e
  end

  private

  def retrieve_pdf_file(pdf_file_data)
    # 从Active Storage中获取文件
    # pdf_file_data应该包含blob_id或其他标识符
    begin
      if pdf_file_data.is_a?(Hash) && pdf_file_data['blob_id']
        # 通过blob_id查找文件
        ActiveStorage::Blob.find_by(id: pdf_file_data['blob_id'])
      elsif pdf_file_data.is_a?(String)
        # 直接通过ID查找
        ActiveStorage::Blob.find_by(id: pdf_file_data)
      else
        Rails.logger.error("[BatchPdfEssayJob] Invalid pdf_file_data format: #{pdf_file_data}")
        nil
      end
    rescue StandardError => e
      Rails.logger.error("[BatchPdfEssayJob] Failed to retrieve PDF file: #{e.message}")
      nil
    end
  end
end
