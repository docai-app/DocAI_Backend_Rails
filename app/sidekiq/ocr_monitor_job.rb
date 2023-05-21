class OcrMonitorJob
  include Sidekiq::Worker

  sidekiq_options retry: 3, dead: true, queue: "ocr", throttle: { threshold: 1, period: 10.second }

  sidekiq_retry_in { |count| 60 * 60 * 1 * count }

  sidekiq_retries_exhausted do |msg, _ex|
    subject = "[Api::CreateOrderWorker]Out of retries! #{msg["class"]} with #{msg["args"]}"
    _message = "error: #{msg["error_message"]}"
  end

  def perform()
    Apartment::Tenant.each do |tenant|
      Apartment::Tenant.switch!(tenant)
      puts "====== tenant: #{tenant} ======"
      @document = Document.where.not(status: :pending).where(content: nil).where(is_document: true).order(Arel.sql("RANDOM()")).first
      if @document.present? && @document.is_document
        ocrRes = RestClient.post ENV["DOCAI_ALPHA_URL"] + "/alpha/ocr", { :document_url => @document.storage_url }
        content = JSON.parse(ocrRes)["result"]
        @document.content = content
        @document.ready!
      else
        puts "====== no document found ======"
      end
    end
  rescue
    puts "====== error ====== document.id: #{@document.id}"
  end
end
