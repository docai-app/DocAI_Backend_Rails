# frozen_string_literal: true

class OcrJob
  include Sidekiq::Worker

  queue_as :ocr

  sidekiq_options retry: 3, dead: true, queue: 'ocr', throttle: { threshold: 1, period: 10.second }

  sidekiq_retry_in { |count| 60 * 60 * 1 * count }

  sidekiq_retries_exhausted do |msg, _ex|
    _message = "error: #{msg['error_message']}"
  end

  def perform(document_id, subdomain)
    Apartment::Tenant.switch!(subdomain)
    document = Document.find(document_id)
    if document.present? && document.is_document && document.content.nil?
      ocr_res = RestClient.post("#{ENV['DOCAI_ALPHA_URL']}/alpha/ocr", document_url: document.storage_url)
      content = JSON.parse(ocr_res)['result']
      puts "====== perform ====== document #{document_id} content: #{content}"
      document.content = content
      document.ready!
    end
    puts "====== perform ====== document #{document_id} was successfully processed"
  rescue StandardError => e
    @document = Document.find(document_id)
    @document.retry_count += 1
    @document.error_message = e.message
    @document.save!
    puts "====== error ====== document.id: #{document_id.id}"
    puts "====== error ====== error: #{e.message}"
  end
end
