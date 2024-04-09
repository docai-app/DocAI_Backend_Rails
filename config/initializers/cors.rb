# frozen_string_literal: true

# Be sure to restart your server when you modify this file.

# Avoid CORS issues when API is called from the frontend app.
# Handle Cross-Origin Resource Sharing (CORS) in order to accept cross-origin AJAX requests.

# Read more: https://github.com/cyu/rack-cors

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins 'http://localhost:3000', 'http://localhost:8080', 'http://localhost:8889', 'http://localhost:8888', 'https://docai.m2mda.com', 'https://docai-dev.m2mda.com', 'https://docai-demo.examhero.com', 'http://docai-demo.examhero.com', 'https://aiadmin.examhero.com', 'http://aiadmin.examhero.com',
            'https://doc-ai-dev-frontend.vercel.app', 'http://doc-ai-dev-frontend.vercel.app', 'https://doc-ai-frontend.vercel.app', 'http://doc-ai-frontend.vercel.app', 'https://test-docai-frontend.vercel.app', 'http://test-docai-frontend.vercel.app', 'https://docai-demo.vercel.app', 'http://docai-demo.vercel.app', 'https://aiadmin.docai.net', 'http://aiadmin.docai.net', 'https://dev-docai-admin-dashboard-frontend.vercel.app', 'https://prod-docai-admin-dashboard-frontend.vercel.app',
            'https://test-dev.docai.net', 'http://test-dev.docai.net', 'https://test.docai.net', 'http://test.docai.net',
            'https://chatbot-demo.docai.net', 'http://chatbot-demo.docai.net', 'https://chatbot.docai.net', 'http://chatbot.docai.net', 'https://prod-docai-chatbot.vercel.app', 'http://prod-docai-chatbot.vercel.app', 'https://dev-docai-chatbot.vercel.app', 'http://dev-docai-chatbot.vercel.app', 'https://docai-chatbot-next.vercel.app', 'http://docai-chatbot-next.vercel.app', 'https://chatbot-dev.docai.net', 'http://chatbot-dev.docai.net', 'https://dev-docai-chatbot-plus.vercel.app', 'http://dev-docai-chatbot-plus.vercel.app/',
            'https://chyb.docai.net', 'http://chyb.docai.net', 'https://*-dev.docai.net', 'http://*-dev.docai.net',
            'https://chyb-dev.docai.net', 'http://chyb-dev.docai.net', 'https://chyb.docai.net', 'http://chyb.docai.net', 'https://chyb-dev.docai.net:8080', 'http://chyb-dev.docai.net:8080',
            'https://wishcoffee-dev.docai.net', 'http://wishcoffee-dev.docai.net', 'https://wishcoffee.docai.net', 'http://wishcoffee.docai.net',
            'https://docai-dev.docai.net', 'http://docai-dev.docai.net', 'https://docai.docai.net', 'http://docai.docai.net',
            'https://hku-dev.docai.net', 'http://hku-dev.docai.net', 'https://hku.docai.net', 'http://hku.docai.net',
            'https://mastercorp-dev.docai.net', 'http://mastercorp-dev.docai.net', 'https://mastercorp.docai.net', 'http://mastercorp.docai.net',
            'https://xinhua-dev.docai.net', 'http://xinhua-dev.docai.net', 'https://xinhua.docai.net', 'http://xinhua.docai.net',
            'https://mjsse-dev.docai.net', 'http://mjsse-dev.docai.net', 'https://mjsse.docai.net', 'http://mjsse.docai.net',
            'https://phc-dev.docai.net', 'http://phc-dev.docai.net', 'https://phc.docai.net', 'http://phc.docai.net',
            'https://test-docai-chatbot-plus.vercel.app', 'https://docai-client.docai.net', 'https://docai-teacher.docai.net'

    # origins Cors.all.pluck(:url)
    # origins *Cors.pluck(:url)

    resource '*',
             headers: :any,
             expose: ['Authorization'],
             methods: %i[get post put patch delete options head]
  end
end
