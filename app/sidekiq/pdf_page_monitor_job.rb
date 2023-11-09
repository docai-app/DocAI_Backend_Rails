# frozen_string_literal: true

class PdfPageMonitorJob
  include Sidekiq::Job

  sidekiq_options retry: 3, dead: true, queue: 'pdf_page_monitor_job', throttle: { threshold: 1, period: 10.second }

  sidekiq_retry_in { |count| 60 * 60 * 1 * count }

  sidekiq_retries_exhausted do |msg, _ex|
    _message = "error: #{msg['error_message']}"
  end

  def perform(*_args)
    puts '====== PdfPageMonitorJob ======'
    Apartment::Tenant.each do |tenant|
      # check if tenant cannot be switched, then skip this tenant and continue to next tenant
      begin
        Apartment::Tenant.switch!(tenant)
      rescue StandardError
        next
      end
      puts "====== tenant: #{tenant} ======"
      @pdf_page_details = PdfPageDetail.where(status: :pending).where(
        'retry_count < ?', 3
      )
      puts "====== PdfPageDetail found: #{@pdf_page_details.length} ======"
      if @pdf_page_details.present?
        @pdf_page_detail = @pdf_page_details.sample
        puts "====== pdf_page_detail id: #{@pdf_page_detail.id} needs to be processed ======"
        PdfPageJob.perform_async(@pdf_page_detail.id, tenant)
        puts "====== perform ====== pdf_page_detail #{@pdf_page_detail.id} was successfully processed"
      else
        puts '====== no pdf_page_detail needs to be processed ======'
      end
    end
  rescue StandardError => e
    puts "====== error ====== error: #{e.message}"
  end
end
