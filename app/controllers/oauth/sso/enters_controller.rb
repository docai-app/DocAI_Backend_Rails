# frozen_string_literal: true

module Oauth
  module Sso
    class EntersController < ActionController::Base
      # Browser navigation endpoint — not an API JSON controller.
      protect_from_forgery with: :null_session
      before_action :switch_public_tenant_for_sso

      # GET /oauth/sso/enter?ticket=...
      def show
        result = TicketConsumer.new(ticket: params[:ticket]).call

        response.set_header('Cache-Control', 'no-store')
        response.set_header('Pragma', 'no-cache')
        response.set_header('Referrer-Policy', 'no-referrer')
        response.set_header('X-Content-Type-Options', 'nosniff')
        apply_frame_ancestors!(result[:session].parent_origin)

        EmbedCookie.set!(
          response: response,
          token: result[:session_token],
          expires_at: result[:session].expires_at,
          public_origin: result[:provider_origin]
        )

        # Absolute URL from launch provider_origin. Relative redirect_to rebuilds from
        # request Host + X-Forwarded-Proto and can emit https://localhost when Next
        # rewrites an http frontend to the HTTPS API.
        redirect_to result[:redirect_url], status: :see_other, allow_other_host: true
      rescue ::Oauth::Sso::Error => e
        render_enter_error(e)
      rescue StandardError => e
        Rails.logger.warn("[Oauth::Sso::Enter] unexpected error=#{e.class}")
        render_enter_error(
          ::Oauth::Sso::Error.new('PROVIDER_UNAVAILABLE', 'AIEnglish 暂时无法开启，请稍后再试。', http_status: 503)
        )
      end

      private

      def switch_public_tenant_for_sso
        Apartment::Tenant.switch!('public') if defined?(Apartment)
      rescue StandardError => e
        Rails.logger.warn("[Oauth::Sso::Enter] tenant switch failed: #{e.class}")
      end

      def apply_frame_ancestors!(parent_origin)
        origins = ["'self'", parent_origin].compact.uniq.join(' ')
        response.set_header('Content-Security-Policy', "frame-ancestors #{origins}")
        # Ensure legacy X-Frame-Options does not block allowed iframe embeds.
        response.headers.delete('X-Frame-Options')
      end

      def render_enter_error(error)
        response.set_header('Cache-Control', 'no-store')
        response.set_header('Referrer-Policy', 'no-referrer')
        status = error.http_status || 400
        html = <<~HTML
          <!doctype html>
          <html lang="zh-Hant">
            <head>
              <meta charset="utf-8" />
              <meta name="viewport" content="width=device-width, initial-scale=1" />
              <title>AIEnglish</title>
              <style>
                body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; background:#faf9f6; color:#1a1a1a; margin:0; }
                main { max-width: 28rem; margin: 15vh auto; padding: 1.5rem; text-align: center; }
                h1 { font-size: 1.25rem; margin-bottom: 0.75rem; }
                p { color:#555; line-height: 1.5; }
              </style>
            </head>
            <body>
              <main>
                <h1>无法开启作业</h1>
                <p>#{ERB::Util.html_escape(error.message)}</p>
                <p>请返回 KonnecAI 后重试。</p>
              </main>
            </body>
          </html>
        HTML
        render html: html.html_safe, status: status
      end
    end
  end
end
