class DocumentClassificationMonitorJob
  include Sidekiq::Worker

  sidekiq_options retry: 3, dead: true, queue: "document_classification", throttle: { threshold: 1, period: 10.second }

  sidekiq_retry_in { |count| 60 * 60 * 1 * count }

  sidekiq_retries_exhausted do |msg, _ex|
    subject = "[Api::CreateOrderWorker]Out of retries! #{msg["class"]} with #{msg["args"]}"
    _message = "error: #{msg["error_message"]}"
  end

  def perform(*args)
    Apartment::Tenant.each do |tenant|
      Apartment::Tenant.switch!(tenant)
      puts "====== tenant: #{tenant} ======"
      @document = Document.where(is_classified: false).where.not(content: nil).where(is_document: true).order(created_at: :desc).first
      if @document.present? && @document.label_ids.first.present?
        puts "document id: #{@document.inspect}, document label: #{@document.label_ids.first}"
        classificationRes = RestClient.post ENV["DOCAI_ALPHA_URL"] + "/classification/confirm", { id: @document.id, label: @document.label_ids.first }.to_json, { content_type: :json, accept: :json }
        puts JSON.parse(classificationRes)
        puts JSON.parse(classificationRes)["status"]
        if JSON.parse(classificationRes)["status"]
          @document.is_classified = true
          @document.confirmed!
        end
      else
        puts "====== no document found ======"
      end
    end
  rescue
    puts "====== error ====== document.id: #{@document.id}"
  end
end
