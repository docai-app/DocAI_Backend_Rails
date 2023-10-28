# frozen_string_literal: true

class OmniauthCallbacksController < Devise::OmniauthCallbacksController
  def google_oauth2
    # Get access tokens from the google server
    puts 'Google Oauth2!'
    puts "omniauth callback: #{request.env['omniauth']}"
    puts "omniauth auth: #{request.env['omniauth.auth']}"
    access_token = request.env['omniauth.auth']
    user = User.find_for_google_oauth2(access_token)
    # Access_token is used to authenticate request made from the rails application to the google server
    google_identity = user.identities.find_by(provider: 'Google')
    google_identity.meta['google_token'] = access_token.credentials.token
    # Refresh_token to request new access_token
    # Note: Refresh_token is only sent once during the first request
    refresh_token = access_token.credentials.refresh_token
    google_identity.meta['google_refresh_token'] = refresh_token if refresh_token.present?
    google_identity.save
    user
  end

  def failure
    # If we do get failures we should probably handle them more explicitly than just rerouting to root. To review in the future with colo
    # redirect_to root_path
    puts 'omniauth failure'
  end
end
