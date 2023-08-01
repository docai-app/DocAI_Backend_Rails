# frozen_string_literal: true

class DocumentClassificationJob
  include Sidekiq::Worker

  sidekiq_options retry: 3, dead: true, queue: 'document_classification', throttle: { threshold: 1, period: 10.second }

  sidekiq_retry_in { |count| 60 * 60 * 1 * count }

  sidekiq_retries_exhausted do |msg, _ex|
    _message = "error: #{msg['error_message']}"
  end

  def perform(document_id, label_id, subdomain)
    Apartment::Tenant.switch!(subdomain)
    document = Document.find(document_id)
    puts document_id, label_id, subdomain
    if document.present? && document.is_document && document.content.present? && !document.is_classifier_trained
      classificationRes = RestClient.post "#{ENV['DOCAI_ALPHA_URL']}/classification/confirm",
                                          { content: document.content, label: label_id, model: subdomain }.to_json, { content_type: :json, accept: :json }
      puts classificationRes
      if JSON.parse(classificationRes)['status']
        document.is_classified = true
        document.is_classifier_trained = true
        document.confirmed!
      end
    end
    puts "====== perform ====== document #{document_id} was successfully processed"
  rescue StandardError => e
    puts "====== error ====== document.id: #{document_id}"
    puts "Document Classification processing failed for document #{document_id}: #{e.message}"
  end
end
