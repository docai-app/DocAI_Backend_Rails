# frozen_string_literal: true

class DocumentSmartExtractionJob
  include Sidekiq::Worker

  sidekiq_options retry: 3, dead: true, queue: "document_smart_extraction", throttle: { threshold: 1, period: 10.second }

  sidekiq_retry_in { |count| 60 * 60 * 1 * count }

  sidekiq_retries_exhausted do |msg, _ex|
    _message = "error: #{msg["error_message"]}"
  end

  def perform(smart_extraction_id, document_id, document_smart_extraction_data_id, subdomain)
    puts "====== perform ====== smart_extraction_id: #{smart_extraction_id}"
    puts "====== perform ====== document_id: #{document_id}"
    puts "====== perform ====== document_smart_extraction_data_id: #{document_smart_extraction_data_id}"
    puts "====== perform ====== subdomain: #{subdomain}"
    Apartment::Tenant.switch!(subdomain)
    puts "====== tenant: #{subdomain} ======"
    @document = Document.find(document_id)
    @smart_extraction_schema = SmartExtractionSchema.find(smart_extraction_id)
    @document_smart_extraction_data = DocumentSmartExtractionDatum.find(document_smart_extraction_data_id)
    res = AiService.documentSmartExtraction(@smart_extraction_schema.schema, @document.content, @smart_extraction_schema.data_schema)
    puts "====== perform ====== res: #{res}"
    if Utils.matchingKeys?(@smart_extraction_schema.data_schema, res)
      puts "====== Match! ======"
      @document_smart_extraction_data.data = res
      @document_smart_extraction_data.is_ready = true
      @document_smart_extraction_data.status = :completed
      @document_smart_extraction_data.save!
    else
      @document_smart_extraction_data.retry_count += 1
      if @document_smart_extraction_data.retry_count >= @document_smart_extraction_data.max_retry
        @document_smart_extraction_data.status = :failed
      else
        @document_smart_extraction_data.status = :retry
      end
      @document_smart_extraction_data.save!
      puts "====== DocumentSmartExtractionDatum retry ======"
    end
  rescue StandardError => e
    puts "====== error ====== error: #{e.message}"
    @document_smart_extraction_data.retry_count += 1
    if @document_smart_extraction_data.retry_count >= @document_smart_extraction_data.max_retry
      @document_smart_extraction_data.status = :failed
    else
      @document_smart_extraction_data.status = :retry
    end
    @document_smart_extraction_data.save!
  end
end
