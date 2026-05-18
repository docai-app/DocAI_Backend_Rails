# frozen_string_literal: true

module HasWechatMiniprogramBinding
  extend ActiveSupport::Concern

  WECHAT_META_KEY = 'wechat_miniprogram'

  module ClassMethods
    def find_by_wechat_miniprogram(app_id:, openid:)
      return nil if openid.blank? || app_id.blank?

      where(
        "meta->'wechat_miniprogram'->>'openid' = ? AND meta->'wechat_miniprogram'->>'wechat_app_id' = ?",
        openid.to_s,
        app_id.to_s
      ).first
    end
  end

  def wechat_miniprogram_bound?
    wechat_miniprogram_openid.present?
  end

  # @return [Hash] safe subset for API JSON (no secrets)
  def wechat_miniprogram_binding_for_response
    s = wechat_miniprogram_slice
    return nil if s.blank? || s['openid'].blank?

    {
      wechat_app_id: s['wechat_app_id'],
      openid: s['openid'],
      unionid: s['unionid'],
      nickname: s['nickname'],
      avatar_url: s['avatar_url'],
      bound_at: s['bound_at'],
      last_login_at: s['last_login_at']
    }.compact
  end

  # @param code [String] wx.login js_code
  # @return [Hash] { ok: true, binding: Hash } or { ok: false, error_code:, message: }
  def bind_with_wechat_code!(code, nickname: nil, avatar_url: nil)
    session = WechatMiniprogram::AuthService.jscode2session(code)
    app_id = WechatMiniprogram::AuthService.app_id
    openid = session['openid'].to_s
    unionid = session['unionid'].presence

    return { ok: false, error_code: 'WECHAT_CODE_INVALID', message: 'Missing openid from WeChat.' } if openid.blank?

    binding_result = nil
    GeneralUser.transaction do
      lock!

      existing_openid = wechat_miniprogram_openid
      if existing_openid.present? && existing_openid != openid
        binding_result = {
          ok: false,
          error_code: 'WECHAT_ALREADY_BOUND',
          message: 'This account is already bound to a different WeChat identity.'
        }
        raise ActiveRecord::Rollback
      end

      conflict = GeneralUser.where(
        "meta->'#{WECHAT_META_KEY}'->>'openid' = ? AND meta->'#{WECHAT_META_KEY}'->>'wechat_app_id' = ?",
        openid,
        app_id
      ).where.not(id: id).first

      if conflict
        binding_result = {
          ok: false,
          error_code: 'WECHAT_OPENID_CONFLICT',
          message: 'This WeChat is already linked to another account.'
        }
        raise ActiveRecord::Rollback
      end

      wm = wechat_miniprogram_slice.merge(
        'wechat_app_id' => app_id,
        'openid' => openid,
        'bound_at' => wechat_miniprogram_slice['bound_at'].presence || Time.current.iso8601
      )
      wm['unionid'] = unionid if unionid.present?
      wm['nickname'] = nickname if nickname.present?
      wm['avatar_url'] = avatar_url if avatar_url.present?

      self.meta = meta.merge(WECHAT_META_KEY => wm)
      save!
      binding_result = { ok: true, binding: wechat_miniprogram_binding_for_response }
    end

    binding_result
  end

  def touch_wechat_miniprogram_last_login!
    s = wechat_miniprogram_slice
    return if s.blank? || s['openid'].blank?

    s['last_login_at'] = Time.current.iso8601
    self.meta = meta.merge(WECHAT_META_KEY => s)
    save!
  end

  private

  def wechat_miniprogram_slice
    h = meta[WECHAT_META_KEY] || meta[WECHAT_META_KEY.to_sym]
    return {} unless h.is_a?(Hash)

    h.stringify_keys
  end

  def wechat_miniprogram_openid
    wechat_miniprogram_slice['openid'].presence
  end
end
