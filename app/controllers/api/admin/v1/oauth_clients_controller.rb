# frozen_string_literal: true

module Api
  module Admin
    module V1
      class OauthClientsController < AdminApiController
        before_action :set_client, only: %i[show update destroy rotate_secret enable disable]

        # GET /api/admin/v1/oauth/clients
        def index
          clients = OauthApplication.order(created_at: :desc)
          render json: {
            status: 'success',
            data: clients.map { |c| c.as_admin_json }
          }
        end

        # GET /api/admin/v1/oauth/clients/:id
        def show
          render json: { status: 'success', data: @client.as_admin_json }
        end

        # POST /api/admin/v1/oauth/clients
        def create
          client = OauthApplication.new(client_params_for_create)
          client.renew_secret
          raw_secret = client.plaintext_secret

          if client.save
            render json: {
              status: 'success',
              data: client.as_admin_json.merge(client_secret: raw_secret),
              message: 'Client created. Store client_secret now; it will not be shown again.'
            }, status: :created
          else
            render json: {
              status: 'error',
              errors: client.errors.full_messages
            }, status: :unprocessable_entity
          end
        end

        # PATCH /api/admin/v1/oauth/clients/:id
        def update
          if @client.update(client_params_for_update)
            render json: { status: 'success', data: @client.as_admin_json }
          else
            render json: {
              status: 'error',
              errors: @client.errors.full_messages
            }, status: :unprocessable_entity
          end
        end

        # DELETE /api/admin/v1/oauth/clients/:id
        def destroy
          @client.destroy!
          render json: { status: 'success', message: 'Client deleted.' }
        end

        # POST /api/admin/v1/oauth/clients/:id/rotate_secret
        def rotate_secret
          @client.renew_secret
          raw_secret = @client.plaintext_secret
          @client.save!
          render json: {
            status: 'success',
            data: @client.as_admin_json.merge(client_secret: raw_secret),
            message: 'Secret rotated. Store client_secret now; it will not be shown again.'
          }
        end

        # POST /api/admin/v1/oauth/clients/:id/enable
        def enable
          @client.update!(enabled: true)
          render json: { status: 'success', data: @client.as_admin_json }
        end

        # POST /api/admin/v1/oauth/clients/:id/disable
        def disable
          @client.update!(enabled: false)
          revoke_client_tokens!(@client)
          render json: { status: 'success', data: @client.as_admin_json }
        end

        private

        def set_client
          @client = OauthApplication.find(params[:id])
        end

        def client_params_for_create
          permitted = params.require(:client).permit(
            :name, :confidential, :enabled, :trusted,
            :logo_url, :homepage_url, :privacy_policy_url, :tos_url, :scopes,
            redirect_uris: []
          )
          normalize_client_attrs(permitted)
        end

        def client_params_for_update
          permitted = params.require(:client).permit(
            :name, :confidential, :enabled, :trusted,
            :logo_url, :homepage_url, :privacy_policy_url, :tos_url, :scopes,
            redirect_uris: []
          )
          normalize_client_attrs(permitted)
        end

        def normalize_client_attrs(permitted)
          attrs = permitted.to_h
          if attrs.key?('redirect_uris') || attrs.key?(:redirect_uris)
            uris = Array(attrs.delete('redirect_uris') || attrs.delete(:redirect_uris))
            attrs['redirect_uri'] = uris.map(&:to_s).map(&:strip).reject(&:blank?).join("\n")
          end
          attrs['scopes'] = Array(attrs['scopes']).join(' ') if attrs['scopes'].is_a?(Array)
          attrs['enabled'] = false if attrs['enabled'].nil? && action_name == 'create'
          attrs
        end

        def revoke_client_tokens!(client)
          Doorkeeper::AccessToken.where(application_id: client.id, revoked_at: nil)
                                 .find_each(&:revoke)
          Doorkeeper::AccessGrant.where(application_id: client.id, revoked_at: nil)
                                 .find_each(&:revoke)
        rescue StandardError => e
          Rails.logger.warn("[OauthClientsController] revoke tokens failed: #{e.message}")
        end
      end
    end
  end
end
