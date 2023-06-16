class FormDeepUnderstandingMonitorJob
  include Sidekiq::Worker

  sidekiq_options retry: 3, dead: true, queue: 'form_deep_understanding_monitor_job',
                  throttle: { threshold: 1, period: 10.second }

  sidekiq_retry_in { |count| 60 * 60 * 1 * count }

  sidekiq_retries_exhausted do |msg, _ex|
    _message = "error: #{msg['error_message']}"
  end

  def perform(*_args)
    puts '====== FormDeepUnderstandingMonitorJob ======'
    Apartment::Tenant.each do |tenant|
      # check if tenant cannot be switched, then skip this tenant and continue to next tenant
      begin
        Apartment::Tenant.switch!(tenant)
      rescue StandardError
        next
      end
      puts "====== tenant: #{tenant} ======"
      # I want to find the last document that meta.needs_deep_understanding is true and meta.is_deep_understanding is false
      @documents = Document.where("meta->>'needs_deep_understanding' != ?", 'false').where("meta->>'is_deep_understanding' = ?", 'false').where(
        "meta->>'needs_approval' != ?", 'nil'
      ).where(is_document: true)
      puts "====== Documents found: #{@documents.length} ======"
      if @documents.present?
        @document = @documents.last
        puts "====== document id: #{@document.id} needs deep understanding ======"
        puts "====== document meta form_schema_id: #{@document.meta['form_schema_id']} ======"
        FormDeepUnderstandingJob.perform_async(@document.id, @document.meta['form_schema_id'],
                                               @document.meta['needs_approval'], tenant)
      else
        puts '====== no document needs deep understanding ======'
      end
    end
  rescue StandardError => e
    puts "====== error ====== error: #{e.message}"
  end
end
