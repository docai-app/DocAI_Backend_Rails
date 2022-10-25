# Be sure to restart your server when you modify this file.

# Avoid CORS issues when API is called from the frontend app.
# Handle Cross-Origin Resource Sharing (CORS) in order to accept cross-origin AJAX requests.

# Read more: https://github.com/cyu/rack-cors

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins "http://localhost:3000", "http://localhost:8080", "https://docai.m2mda.com", "https://docai-dev.m2mda.com", "https://doc-ai-dev-frontend.vercel.app", "http://doc-ai-dev-frontend.vercel.app", "https://doc-ai-frontend.vercel.app", "http://doc-ai-frontend.vercel.app", "https://chyb.docai.net", "http://chyb.docai.net"

    resource "*",
      headers: :any,
      expose: ["Authorization"],
      methods: [:get, :post, :put, :patch, :delete, :options, :head]
  end
end
