# frozen_string_literal: true

module Api
  module V1
    module Oauth
      # Partner reports local account binding after OAuth login.
      # Auth: Bearer OAuth access_token (user must match general_user_id / sub).
      class PartnerBindingsController < ApplicationController
        include Doorkeeper::Rails::Helpers

        before_action -> { doorkeeper_authorize! }

        # POST /api/v1/oauth/partner_bindings
        def create
          user = GeneralUser.find_by(id: doorkeeper_token.resource_owner_id)
          application = OauthApplication.find_by(id: doorkeeper_token.application_id)

          if user.blank? || application.blank?
            return render json: { status: 'error', errors: ['Invalid token subject or client'] },
                          status: :unauthorized
          end

          unless application.enabled?
            return render json: { status: 'error', errors: ['Client is disabled'] },
                          status: :forbidden
          end

          requested_user_id = params[:general_user_id].presence || user.id.to_s
          if requested_user_id.to_s != user.id.to_s
            return render json: {
              status: 'error',
              errors: ['general_user_id must match the access token subject (sub)']
            }, status: :forbidden
          end

          external_user_id = params.require(:external_user_id).to_s.strip
          if external_user_id.blank?
            return render json: { status: 'error', errors: ['external_user_id is required'] },
                          status: :unprocessable_entity
          end

          external_site = params[:external_site].to_s.strip.presence || application.homepage_url

          link = OauthPartnerAccountLink.upsert_active!(
            application: application,
            general_user: user,
            external_user_id: external_user_id,
            external_site: external_site,
            meta: { via: 'partner_bindings_api' }
          )

          OauthAuditLog.record!(
            event: 'partner_binding_upserted',
            application: application,
            general_user: user,
            request: request,
            meta: {
              via: 'partner_bindings_api',
              external_user_id: external_user_id,
              external_site: external_site,
              link_id: link.id
            }
          )

          Oauth::WebhookDispatcher.enqueue_event(
            application: application,
            event_type: 'oauth.binding.created',
            data: {
              general_user_id: user.id,
              external_user_id: link.external_user_id,
              external_site: link.external_site,
              linked_at: link.linked_at.utc.iso8601
            }
          )

          render json: {
            status: 'success',
            data: {
              id: link.id,
              general_user_id: link.general_user_id,
              external_user_id: link.external_user_id,
              external_site: link.external_site,
              status: link.status,
              linked_at: link.linked_at
            }
          }, status: :created
        end
      end
    end
  end
end
