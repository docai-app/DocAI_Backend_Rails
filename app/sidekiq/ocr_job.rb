class OcrJob
  include Sidekiq::Worker
  sidekiq_options retry: 7, dead: true, queue: "ocr", throttle: { threshold: 1, period: 5.second }

  sidekiq_retry_in { |count| 60 * 60 * 24 * count }

  sidekiq_retries_exhausted do |msg, _ex|
    subject = "[Api::CreateOrderWorker]Out of retries! #{msg["class"]} with #{msg["args"]}"
    _message = "error: #{msg["error_message"]}"
  end

  def perform()
    # Do something
    @document = Document.where(status: "uploaded").order(created_at: :desc).first
    if @document.present?
      ocrRes = RestClient.post ENV["DOCAI_ALPHA_URL"] + "/alpha/ocr", { :document_url => @document.storage_url }
      content = JSON.parse(ocrRes)["result"]
      @document.content = content
      @document.ready!
    end
  rescue
    puts "====== error ====== document.id: #{content}"
  end
end
