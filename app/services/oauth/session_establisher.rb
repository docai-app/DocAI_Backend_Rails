# frozen_string_literal: true

module Oauth
  module SessionEstablisher
    SESSION_KEY = :oauth_general_user_id

    module_function

    def establish!(session, general_user)
      return unless general_user

      session[SESSION_KEY] = general_user.id
      general_user
    end

    def clear!(session)
      session.delete(SESSION_KEY)
    end

    def current(session)
      id = session[SESSION_KEY]
      return if id.blank?

      GeneralUser.find_by(id: id)
    end
  end
end
