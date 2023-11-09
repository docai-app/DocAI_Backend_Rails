# frozen_string_literal: true

require 'addressable'

class PdfPagesCreationJob
  include Sidekiq::Job

  queue_as :pdf_pages_creation

  sidekiq_options retry: 3, dead: true, queue: 'ocr', throttle: { threshold: 1, period: 10.second }

  sidekiq_retry_in { |count| 60 * 60 * 1 * count }

  sidekiq_retries_exhausted do |msg, _ex|
    _message = "error: #{msg['error_message']}"
  end

  def perform(document_id, subdomain)
    puts "====== perform ====== document_id: #{document_id} subdomain: #{subdomain}"
    Apartment::Tenant.switch!(subdomain)
    document = Document.find(document_id)
    io = URI.open(Addressable::URI.parse(document.storage_url).normalize.to_s)
    reader = PDF::Reader.new(io)
    page_count = reader.page_count
    puts "Page count: #{page_count}"

    ActiveRecord::Base.transaction do
      page_count.times do |page_number|
        PdfPageDetail.create!(
          document:,
          page_number:,
          status: 0
        )
      end
    end
  end
end
