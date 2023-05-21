class DocumentClassificationJob
  include Sidekiq::Worker

  sidekiq_options retry: 3, dead: true, queue: "document_classification", throttle: { threshold: 1, period: 10.second }

  sidekiq_retry_in { |count| 60 * 60 * 1 * count }

  sidekiq_retries_exhausted do |msg, _ex|
    subject = "[Api::CreateOrderWorker]Out of retries! #{msg["class"]} with #{msg["args"]}"
    _message = "error: #{msg["error_message"]}"
  end

  def perform(document_id, label_id, subdomain)
    Apartment::Tenant.switch!(subdomain)
    document = Document.find(document_id)
    if document.present? && document.is_document && !document.is_classified && document.content.present?
      classificationRes = RestClient.post ENV["DOCAI_ALPHA_URL"] + "/classification/confirm", { id: document_id, label: label_id }.to_json, { content_type: :json, accept: :json }
      if JSON.parse(classificationRes)["status"]
        document.is_classified = true
        document.confirmed!
      end
    end
  rescue
    puts "====== error ====== document.id: #{document_id}"
    puts "Document Classification processing failed for document #{document_id}: #{e.message}"
  end
end
