# frozen_string_literal: true

class DocumentEmbeddingMonitorJob
  include Sidekiq::Worker

  sidekiq_options retry: 3, dead: true, queue: 'document_embedding_monitor_job',
                  throttle: { threshold: 1, period: 10.second }

  sidekiq_retry_in { |count| 60 * 60 * 1 * count }

  sidekiq_retries_exhausted do |msg, _ex|
    _message = "error: #{msg['error_message']}"
  end

  def perform(*_args)
    puts '====== DocumentEmbeddingMonitorJob ======'
    Apartment::Tenant.each do |tenant|
      # check if tenant cannot be switched, then skip this tenant and continue to next tenant
      begin
        Apartment::Tenant.switch!(tenant)
      rescue StandardError
        next
      end
      puts "====== tenant: #{tenant} ======"
      @documents = Document.where.not(content: nil).where(is_document: true).where(is_embedded: false).order('created_at': :desc).first(20)
      puts "====== Documents found: #{@documents.length} ======"
      next unless @documents.present?

      @document = @documents.first
      puts "====== document id: #{@document.id} needs embedding ======"
      puts @document.inspect
      # DocumentEmbeddingJob.perform_async(@document.id, tenant)
      embeddingRes = RestClient.post("#{ENV['DOCAI_ALPHA_URL']}/documents/embedding", {
        document: @document, schema: tenant
      }.to_json, { content_type: :json })
      embeddingRes = JSON.parse(embeddingRes)
      puts "====== embeddingRes: #{embeddingRes}"
      if embeddingRes['status'] == true
        puts "====== document #{@document.id} was successfully processed"
        @document.is_embedded = true
        @document.save!
      else
        puts "====== document #{@document.id} was not successfully processed, error: #{embeddingRes}"
      end
    end
  rescue StandardError => e
    puts "====== error ====== error: #{e.message}"
  end
end
