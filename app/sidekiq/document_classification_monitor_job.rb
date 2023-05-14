class DocumentClassificationMonitorJob
  include Sidekiq::Worker

  sidekiq_options retry: 3, dead: true, queue: "document_classification", throttle: { threshold: 1, period: 10.second }

  sidekiq_retry_in { |count| 60 * 60 * 1 * count }

  sidekiq_retries_exhausted do |msg, _ex|
    subject = "[Api::CreateOrderWorker]Out of retries! #{msg["class"]} with #{msg["args"]}"
    _message = "error: #{msg["error_message"]}"
  end

  def perform(*args)
    # Do something
    @document = Document.where(is_classified: false).where.not(content: nil).where(is_document: true).order(created_at: :desc).first
    if @document.present? && @document.is_document
      classificationRes = RestClient.post ENV["DOCAI_ALPHA_URL"] + "/classification/confirm", { id: @document.id, label: @document.label_ids.first }.to_json, { content_type: :json, accept: :json }
      if JSON.parse(classificationRes)["status"]
        @document.is_classified = true
        @document.confirmed!
      end
    end
  rescue
    puts "====== error ====== document.id: #{@document.id}"
  end
end
