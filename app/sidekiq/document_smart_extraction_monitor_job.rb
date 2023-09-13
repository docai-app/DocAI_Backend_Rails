# frozen_string_literal: true

class DocumentSmartExtractionMonitorJob
  include Sidekiq::Worker

  sidekiq_options retry: 3, dead: true, queue: "document_smart_extraction_monitor_job",
                  throttle: { threshold: 1, period: 10.second }

  sidekiq_retry_in { |count| 60 * 60 * 1 * count }

  sidekiq_retries_exhausted do |msg, _ex|
    _message = "error: #{msg["error_message"]}"
  end

  def perform(*_args)
    puts "====== DocumentSmartExtractionMonitorJob ======"
    Apartment::Tenant.each do |tenant|
      begin
        Apartment::Tenant.switch!(tenant)
      rescue StandardError
        next
      end
      puts "====== tenant: #{tenant} ======"
      @document_smart_extraction_datum = DocumentSmartExtractionDatum.where(is_ready: false).where.not(status: :failed).where("retry_count < ?", 3)
      puts "====== DocumentSmartExtractionDatum found: #{@document_smart_extraction_datum.length} ======"
      if @document_smart_extraction_datum.present?
        # Randomly select one document_smart_extraction_datum to run
        @document_smart_extraction_data = @document_smart_extraction_datum.sample
        @smart_extraction_schema = SmartExtractionSchema.find(@document_smart_extraction_data.smart_extraction_schema_id)
        @document = Document.find(@document_smart_extraction_data.document_id)
        puts "====== document_smart_extraction_data id: #{@document_smart_extraction_data.id} ======"
        DocumentSmartExtractionJob.perform_async(@smart_extraction_schema.id, @document.id,
                                                 @document_smart_extraction_data.id, tenant)
      else
        puts "====== no document_smart_extraction_data needs to be processed ======"
      end
    end
  rescue StandardError => e
    puts "====== error ====== error: #{e.message}"
  end
end
