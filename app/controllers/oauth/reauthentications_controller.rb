# frozen_string_literal: true

module Oauth
  # Partner-facing: clear AS session then continue to /oauth/authorize.
  # Used so "Log in with AIEnglish" always shows the account login form,
  # even when a previous AS session cookie still exists.
  class ReauthenticationsController < ApplicationController
    # GET /oauth/reauthenticate?return_to={authorize_url}
    def show
      return_to = params[:return_to].to_s
      unless Oauth::ReturnToValidator.valid?(return_to)
        return render plain: 'Invalid return_to', status: :bad_request
      end

      Oauth::SessionEstablisher.clear!(session)
      # Avoid prompt=login loops if partner still includes it on authorize URL.
      dest = Oauth::ReturnToValidator.strip_prompt_values(return_to, %w[login])
      unless Oauth::ReturnToValidator.valid?(dest)
        return render plain: 'Invalid return_to', status: :bad_request
      end

      redirect_to dest, allow_other_host: true
    end
  end
end
