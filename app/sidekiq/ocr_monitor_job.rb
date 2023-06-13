# frozen_string_literal: true

class OcrMonitorJob
  include Sidekiq::Worker

  sidekiq_options retry: 3, dead: true, queue: 'ocr_monitor_job', throttle: { threshold: 1, period: 10.second }

  sidekiq_retry_in { |count| 60 * 60 * 1 * count }

  sidekiq_retries_exhausted do |msg, _ex|
    _message = "error: #{msg['error_message']}"
  end

  def perform
    puts '====== OcrMonitorJob ======'
    Apartment::Tenant.each do |tenant|
      # check if tenant cannot be switched, then skip this tenant and continue to next tenant
      begin
        Apartment::Tenant.switch!(tenant)
      rescue StandardError
        next
      end
      puts "====== tenant: #{tenant} ======"
      @documents = Document.where(content: nil).where(is_document: true)
      puts "====== Documents found: #{@documents.length} ======"
      if @documents.present?
        @document = @documents.last
        puts "====== document id: #{@document.id} needs ocr ======"
        OcrJob.perform_async(@document.id, tenant)
        puts "====== perform ====== document #{@document.id} was successfully processed"
      else
        puts '====== no document needs ocr ======'
      end
    end
  rescue StandardError => e
    puts "====== error ====== error: #{e.message}"
  end
end
