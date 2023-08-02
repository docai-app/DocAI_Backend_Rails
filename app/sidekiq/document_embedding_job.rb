# frozen_string_literal: true

class DocumentEmbeddingJob
  include Sidekiq::Worker

  sidekiq_options retry: 3, dead: true, queue: 'document_embedding', throttle: { threshold: 1, period: 10.second }

  sidekiq_retry_in { |count| 60 * 60 * 1 * count }

  sidekiq_retries_exhausted do |msg, _ex|
    _message = "error: #{msg['error_message']}"
  end

  def perform(document_id, subdomain)
    Apartment::Tenant.switch!(subdomain)
    puts "====== perform ====== document_id: #{document_id}"
    puts "====== perform ====== subdomain: #{subdomain}"
    @document = Document.find(document_id)
    puts @document.inspect
    if @document.present? && @document.is_document && @document.content.present? && !@document.is_embedded
      puts "====== document #{@document.id} is not embedded"
      puts @document.inspect
      embeddingRes = RestClient.post("#{ENV['DOCAI_ALPHA_URL']}/documents/embedding", {
                                       document: @document, schema: subdomain
                                     }, { content_type: :json })
      embeddingRes = JSON.parse(embeddingRes)
      puts "====== embeddingRes: #{embeddingRes}"
      if embeddingRes['status'] == true
        puts "====== document #{@document.id} was successfully processed"
        @document.is_embedded = true
        @document.save!
      else
        puts "====== document #{@document.id} was not successfully processed, error: #{embeddingRes}"
      end
    else
      puts "====== document #{@document.id} was not successfully processed"
    end
  end
end
