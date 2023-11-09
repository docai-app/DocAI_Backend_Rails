# frozen_string_literal: true

class PdfPageJob
  include Sidekiq::Job

  sidekiq_options retry: 3, dead: true, queue: 'pdf_page', throttle: { threshold: 1, period: 10.second }

  sidekiq_retry_in { |count| 60 * 60 * 1 * count }

  sidekiq_retries_exhausted do |msg, _ex|
    _message = "error: #{msg['error_message']}"
  end

  def perform(pdf_page_detail_id, tenant)
    Apartment::Tenant.switch!(tenant)
    pdf_page_detail = PdfPageDetail.find(pdf_page_detail_id)
    pdf_page_detail_embedding = VectorDbPgEmbedding.where("cmetadata->>'schema' = ?", tenant).where("cmetadata->>'document_id' = ?", pdf_page_detail.document_id).where(
      "cmetadata->>'page' = ?", pdf_page_detail.page_number.to_s
    ).first
    if pdf_page_detail_embedding.present?
      res = RestClient.post "#{ENV['PORMHUB_URL']}/prompts/pdf_page_detail_summary_keywords_extraction/run.json", { params: {
        content: pdf_page_detail_embedding['document']
      } }
      res = JSON.parse(res)
      puts "Response from OpenAI: #{res}"
      pdf_page_detail.update!(summary: res['data']['summary'], keywords: res['data']['keywords'])
      pdf_page_detail.mark_completed
    else
      pdf_page_detail.mark_failed
      pdf_page_detail.update!(error_message: 'Embedding not found')
      pdf_page_detail.retry_processing
      puts '====== Embedding not found ======'
    end
    puts "====== pdf_page_detail #{pdf_page_detail_id} was successfully processed"
  rescue StandardError => e
    pdf_page_detail = PdfPageDetail.find(pdf_page_detail_id)
    pdf_page_detail.mark_failed
    pdf_page_detail.update!(error_message: e.message)
    pdf_page_detail.retry_processing
    puts "====== Error: #{e.message} ======"
  end
end
