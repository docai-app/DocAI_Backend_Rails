# frozen_string_literal: true

module Api
  module Admin
    module V1
      class OauthClientsController < AdminApiController
        before_action :set_client, only: %i[
          show update destroy rotate_secret enable disable
          account_links webhook update_webhook test_webhook rotate_webhook_secret webhook_deliveries
        ]

        # GET /api/admin/v1/oauth/clients
        def index
          clients = OauthApplication.order(created_at: :desc)
          render json: {
            status: 'success',
            data: clients.map { |c| c.as_admin_json(include_stats: true) }
          }
        end

        # GET /api/admin/v1/oauth/clients/:id
        def show
          render json: {
            status: 'success',
            data: @client.as_admin_json(include_stats: true)
          }
        end

        # POST /api/admin/v1/oauth/clients
        def create
          client = OauthApplication.new(client_params_for_create)
          client.renew_secret
          raw_secret = client.plaintext_secret

          if client.save
            client.ensure_webhook_config!
            render json: {
              status: 'success',
              data: client.as_admin_json(include_stats: true).merge(client_secret: raw_secret),
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
            render json: { status: 'success', data: @client.as_admin_json(include_stats: true) }
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
            data: @client.as_admin_json(include_stats: true).merge(client_secret: raw_secret),
            message: 'Secret rotated. Store client_secret now; it will not be shown again.'
          }
        end

        # POST /api/admin/v1/oauth/clients/:id/enable
        def enable
          @client.update!(enabled: true)
          render json: { status: 'success', data: @client.as_admin_json(include_stats: true) }
        end

        # POST /api/admin/v1/oauth/clients/:id/disable
        def disable
          @client.update!(enabled: false)
          revoke_client_tokens!(@client)
          OauthPartnerAccountLink.revoke_all_for_application!(
            application_id: @client.id,
            reason: 'admin_disable_client'
          )
          render json: { status: 'success', data: @client.as_admin_json(include_stats: true) }
        end

        # GET /api/admin/v1/oauth/clients/:id/account_links
        def account_links
          scope = @client.partner_account_links.includes(:general_user).order(linked_at: :desc)
          status = params[:status].to_s
          scope = scope.where(status: status) if %w[active revoked].include?(status)

          q = params[:q].to_s.strip
          if q.present?
            scope = scope.left_joins(:general_user).where(
              'oauth_partner_account_links.external_user_id ILIKE :q OR general_users.email ILIKE :q OR general_users.nickname ILIKE :q',
              q: "%#{ActiveRecord::Base.sanitize_sql_like(q)}%"
            )
          end

          page = [params[:page].to_i, 1].max
          per_page = [[params[:per_page].to_i, 1].max, 100].min
          per_page = 20 if params[:per_page].blank?
          total = scope.count
          items = scope.offset((page - 1) * per_page).limit(per_page)

          render json: {
            status: 'success',
            data: {
              items: items.map(&:as_admin_json),
              pagination: {
                page: page,
                per_page: per_page,
                total: total
              },
              stats: @client.admin_stats
            }
          }
        end

        # GET /api/admin/v1/oauth/clients/:id/webhook
        def webhook
          config = @client.ensure_webhook_config!
          render json: { status: 'success', data: config.as_admin_json }
        end

        # PUT /api/admin/v1/oauth/clients/:id/webhook
        def update_webhook
          config = @client.ensure_webhook_config!
          attrs = webhook_params
          if config.update(attrs)
            render json: { status: 'success', data: config.as_admin_json }
          else
            render json: { status: 'error', errors: config.errors.full_messages },
                   status: :unprocessable_entity
          end
        end

        # POST /api/admin/v1/oauth/clients/:id/webhook/test
        def test_webhook
          config = @client.ensure_webhook_config!
          if config.url.blank? || config.signing_secret.blank?
            return render json: {
              status: 'error',
              errors: ['Webhook URL and signing_secret are required before testing']
            }, status: :unprocessable_entity
          end

          delivery = Oauth::WebhookDispatcher.enqueue_event(
            application: @client,
            event_type: 'webhook.ping',
            data: {
              message: 'AIEnglish webhook test ping',
              sent_at: Time.current.utc.iso8601
            },
            force: true
          )

          render json: {
            status: 'success',
            data: delivery&.as_admin_json,
            message: 'Test delivery enqueued.'
          }
        end

        # POST /api/admin/v1/oauth/clients/:id/webhook/rotate_secret
        def rotate_webhook_secret
          config = @client.ensure_webhook_config!
          config.renew_signing_secret!
          config.save!
          render json: {
            status: 'success',
            data: config.as_admin_json(include_secret: true),
            message: 'Webhook signing_secret rotated. Store it now; it will not be shown again.'
          }
        end

        # GET /api/admin/v1/oauth/clients/:id/webhook/deliveries
        def webhook_deliveries
          page = [params[:page].to_i, 1].max
          per_page = [[params[:per_page].to_i, 1].max, 100].min
          per_page = 20 if params[:per_page].blank?

          scope = @client.webhook_deliveries.order(created_at: :desc)
          total = scope.count
          items = scope.offset((page - 1) * per_page).limit(per_page)

          render json: {
            status: 'success',
            data: {
              items: items.map(&:as_admin_json),
              pagination: { page: page, per_page: per_page, total: total }
            }
          }
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

        def webhook_params
          permitted = params.require(:webhook).permit(
            :enabled, :url, :timeout_seconds, :max_retries,
            subscribed_events: [],
            custom_headers: {}
          )
          permitted.to_h
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
