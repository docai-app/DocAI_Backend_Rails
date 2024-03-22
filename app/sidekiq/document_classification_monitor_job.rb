# frozen_string_literal: true

class DocumentClassificationMonitorJob
  include Sidekiq::Worker

  sidekiq_options retry: 3, dead: true, queue: 'document_classification_monitor_job',
                  throttle: { threshold: 1, period: 10.second }

  sidekiq_retry_in { |count| 60 * 60 * 1 * count }

  sidekiq_retries_exhausted do |msg, _ex|
    _message = "error: #{msg['error_message']}"
  end

  def perform(*_args)
    puts '====== DocumentClassificationMonitorJob ======'
    Apartment::Tenant.each do |tenant|
      # check if tenant cannot be switched, then skip this tenant and continue to next tenant
      begin
        Apartment::Tenant.switch!(tenant)
      rescue StandardError
        next
      end
      puts "====== tenant: #{tenant} ======"
      @documents = Document.where(is_classified: true).where.not(content: nil).where.not(content: '').where('LENGTH(content) > ?', 10).where(is_document: true).where(is_classifier_trained: false).where(
        'retry_count < ?', 3
      ).order('created_at': :desc)
      puts "====== Documents found: #{@documents.length} ======"
      if @documents.present? && @documents.count > 20
        if ENV['IS_LOCAL'].present? && ENV['IS_LOCAL'] == 'true'
          puts '====== perform ====== local mode does not need classification training ======'
          next
        else
          puts '====== perform ====== classification training ======'
          DocumentClassificationRetrainJob.perform_async(tenant)
        end
      else
        puts '====== no document needs classification ======'
      end
    end
  rescue StandardError => e
    puts "====== error ====== error: #{e.message}"
  end
end
