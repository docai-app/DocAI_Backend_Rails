# frozen_string_literal: true

OpenAI.configure do |config|
  config.access_token = if Rails.env.test?
                          ENV.fetch('OPENAI_API_ACCESS_TOKEN', 'test-openai-token')
                        else
                          ENV.fetch('OPENAI_API_ACCESS_TOKEN')
                        end
end
