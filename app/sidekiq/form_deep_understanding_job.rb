class FormDeepUnderstandingJob
  include Sidekiq::Worker
  
  sidekiq_options retry: 3, dead: true, queue: "form_deep_understanding", throttle: { threshold: 1, period: 10.second }

  sidekiq_retry_in { |count| 60 * 60 * 1 * count }

  sidekiq_retries_exhausted do |msg, _ex|
    subject = "[Api::CreateOrderWorker]Out of retries! #{msg["class"]} with #{msg["args"]}"
    _message = "error: #{msg["error_message"]}"
  end

  def perform(document_id, form_schema_id, needs_approval)
    puts "====== perform ====== document_id: #{document_id}"
    puts "====== perform ====== form_schema_id: #{form_schema_id}"
    puts "====== perform ====== needs_approval: #{needs_approval}"
    @document = Document.find(document_id)
    @form_schema = FormSchema.find(form_schema_id)
    recognizeRes = RestClient.post ENV["DOCAI_ALPHA_URL"] + "/alpha/form/recognize", { :document_url => @document.storage_url, :model_id => @form_schema.azure_form_model_id }
    recognizeRes = JSON.parse(recognizeRes)
    @form_data = FormDatum.new(data: recognizeRes["recognized_form_data"], form_schema_id: FormSchema.where(azure_form_model_id: @form_schema.azure_form_model_id).first.id, document_id: @document.id)
    @form_data.save
    if needs_approval == "true"
      @document_approval = DocumentApproval.new(document_id: @document.id, form_data_id: @form_data.id, approval_status: 0)
      @document_approval.save
    end
  rescue
    puts "====== error ====== document.id: #{document_id}"
  end
end
