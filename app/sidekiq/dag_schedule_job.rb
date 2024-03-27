# frozen_string_literal: true

class DagScheduleJob
  include Sidekiq::Worker

  queue_as :dag_scheduler_job

  sidekiq_options retry: 3, dead: true, queue: 'dag_scheduler_job', throttle: { threshold: 1, period: 10.second }

  sidekiq_retry_in { |count| 60 * 60 * 1 * count }

  sidekiq_retries_exhausted do |msg, _ex|
    _message = "error: #{msg['error_message']}"
  end

  def perform(_dag_id, _cron, _user_id, _entity_name)
    Apartment::Tenant.switch!(subdomain)

    tanent = Utils.extractRequestTenantByToken(request)
    dr = DagRun.new(user: api_user, dag_name: Dag.normalize_name(params[:dag_name]), tanent:)
    dr['meta']['params'] = params.permit!.to_h['params']
    dr.chatbot_id = params[:chatbot_id]
    # binding.pry
    if dr.save
      dr.reset_workflow!
      dr.reload
      dr.start
      json_success(dr)
    else
      json_fail
    end
  rescue StandardError => e
    @document = Document.find(document_id)
    @document.retry_count += 1
    @document.error_message = e.message
    @document.save!
    puts "====== error ====== document.id: #{document_id.id}"
    puts "====== error ====== error: #{e.message}"
  end
end
