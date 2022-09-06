class OcrJob
  include Sidekiq::Job
  sidekiq_options retry: 7, dead: true, queue: :ocr

  sidekiq_retry_in { |count| 60 * 60 * 24 * count }

  sidekiq_retries_exhausted do |msg, _ex|
    subject = "[Api::CreateOrderWorker]Out of retries! #{msg["class"]} with #{msg["args"]}"
    _message = "error: #{msg["error_message"]}"
  end

  def perform(document_id)
    # Do something
    @document = Document.find(document_id)
    puts @document.inspect
    ocrRes = RestClient.post ENV["DOCAI_ALPHA_URL"] + "/alpha/ocr", { :document_url => @document.storage_url }
    content = JSON.parse(ocrRes)["result"]
    @document.content = content
    @document.ready!
  rescue
    puts "====== error ====== document.id: #{content}"
  end
end
