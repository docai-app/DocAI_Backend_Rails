# frozen_string_literal: true

class UpdateChatbotAssistiveQuestionsJob
  include Sidekiq::Job

  sidekiq_options retry: 3, dead: true, queue: 'update_chatbot_assistive_questions_job',
                  throttle: { threshold: 1, period: 10.second }

  sidekiq_retry_in { |count| 60 * 60 * 1 * count }

  sidekiq_retries_exhausted do |msg, _ex|
    _message = "error: #{msg['error_message']}"
  end

  def perform(chatbot_id, metadata, subdomain)
    puts "====== perform ====== chatbot_id: #{chatbot_id} metadata: #{metadata} subdomain: #{subdomain}"
    Apartment::Tenant.switch!(subdomain)
    @chatbot = Chatbot.find(chatbot_id)
    metadata['language'] = @chatbot.meta['language'] || '繁體中文'
    @chatbot.update_assistive_questions(subdomain, metadata)
  end
end
