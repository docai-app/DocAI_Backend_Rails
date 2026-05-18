# frozen_string_literal: true

module WechatMiniprogram
  class AuthService
    class Error < StandardError; end
    class WechatError < Error; end
    class ConfigurationError < Error; end

    DEFAULT_JSCODE2SESSION_URL = 'https://api.weixin.qq.com/sns/jscode2session'

    class << self
      def app_id
        ENV['WECHAT_MINIPROGRAM_APP_ID'].to_s
      end

      def app_secret
        ENV['WECHAT_MINIPROGRAM_APP_SECRET'].to_s
      end

      # @param code [String] wx.login temporary code
      # @return [Hash] raw WeChat JSON (string keys); raises WechatError / ConfigurationError
      def jscode2session(code)
        raise WechatError, 'js_code is required.' if code.blank?

        raise ConfigurationError, 'WECHAT_MINIPROGRAM_APP_ID is not configured.' if app_id.blank?
        raise ConfigurationError, 'WECHAT_MINIPROGRAM_APP_SECRET is not configured.' if app_secret.blank?

        url = ENV.fetch('WECHAT_MINIPROGRAM_JSCODE2SESSION_URL', DEFAULT_JSCODE2SESSION_URL)
        response = RestClient.get(url, params: {
                                    appid: app_id,
                                    secret: app_secret,
                                    js_code: code.to_s,
                                    grant_type: 'authorization_code'
                                  })
        data = JSON.parse(response.body)
        err = data['errcode']
        if err.present? && err != 0
          raise WechatError, data['errmsg'].presence || "WeChat errcode #{err}"
        end

        data
      rescue RestClient::Exception => e
        Rails.logger.error("[WechatMiniprogram::AuthService] #{e.class}: #{e.message}")
        raise WechatError, 'WeChat jscode2session request failed.'
      rescue JSON::ParserError => e
        Rails.logger.error("[WechatMiniprogram::AuthService] Invalid JSON: #{e.message}")
        raise WechatError, 'Invalid response from WeChat.'
      end
    end
  end
end
