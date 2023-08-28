# frozen_string_literal: true

# Be sure to restart your server when you modify this file.

# Avoid CORS issues when API is called from the frontend app.
# Handle Cross-Origin Resource Sharing (CORS) in order to accept cross-origin AJAX requests.

# Read more: https://github.com/cyu/rack-cors

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins 'http://localhost:3000', 'http://localhost:8080', 'https://docai.m2mda.com', 'https://docai-dev.m2mda.com', 'https://docai-demo.examhero.com', 'http://docai-demo.examhero.com', 'https://aiadmin.examhero.com', 'http://aiadmin.examhero.com',
            'https://doc-ai-dev-frontend.vercel.app', 'http://doc-ai-dev-frontend.vercel.app', 'https://doc-ai-frontend.vercel.app', 'http://doc-ai-frontend.vercel.app', 'https://docai-demo.vercel.app', 'http://docai-demo.vercel.app', 'https://aiadmin.docai.net', 'http://aiadmin.docai.net',
            'https://test-dev.docai.net', 'http://test-dev.docai.net', 'https://test.docai.net', 'http://test.docai.net',
            'https://chatbot-demo.docai.net', 'http://chatbot-demo.docai.net', 'https://chatbot.docai.net', 'http://chatbot.docai.net',
            'https://chyb.docai.net', 'http://chyb.docai.net', 'https://*-dev.docai.net', 'http://*-dev.docai.net',
            'https://chyb-dev.docai.net', 'http://chyb-dev.docai.net', 'https://chyb.docai.net', 'http://chyb.docai.net', 'https://chyb-dev.docai.net:8080', 'http://chyb-dev.docai.net:8080',
            'https://wishcoffee-dev.docai.net', 'http://wishcoffee-dev.docai.net', 'https://wishcoffee.docai.net', 'http://wishcoffee.docai.net',
            'https://docai-dev.docai.net', 'http://docai-dev.docai.net', 'https://docai.docai.net', 'http://docai.docai.net'

    resource '*',
             headers: :any,
             expose: ['Authorization'],
             methods: %i[get post put patch delete options head]
  end
end
