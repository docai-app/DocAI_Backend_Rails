# frozen_string_literal: true

class Api::V1::ListeningMaterialsController < ApiController
  include ::Oauth::Sso::EmbedAuthenticatable
  before_action :authenticate_embed_or_general_user!
  before_action :authorize_teacher!
  rescue_from ListeningQgMaterialClient::Error, with: :service_unavailable

  def index
    data = ListeningQgMaterialClient.new.list(query: params[:query], page: params[:page])
    articles = Array(data['articles']).map do |article|
      article.slice('id', 'title', 'source').merge('levels' => Array(article['levels']).map { |level|
        level.slice('version_id', 'level', 'word_count', 'audio_ready')
      })
    end
    render json: { success: true, data: { articles: articles, next_page: data['next_page'] } }
  end

  def show
    render_detail(ListeningQgMaterialClient.new.detail(params[:id]))
  end

  def generate_audio
    unless params[:confirm_paid] == true
      return render json: { success: false, error: 'Confirm audio generation first.' }, status: :unprocessable_entity
    end
    render_detail(ListeningQgMaterialClient.new.generate_audio(params[:id], retry_failed: params[:retry_failed] == true))
  end

  private

  def authorize_teacher!
    response.headers['Cache-Control'] = 'no-store'
    user = current_general_user
    # Assignment-scoped embed sessions are not catalog/paid-generation authority.
    allowed = ListeningTeacherAccess.allowed?(user, embed: embed_session?)
    render json: { success: false, error: 'Listening teacher access is required.' }, status: :forbidden unless allowed
  end

  def render_detail(data)
    safe = data.slice('version_id', 'news_feed_id', 'title', 'level', 'word_count', 'plain_transcript')
    safe['audio'] = (data['audio'] || {}).slice('status', 'retryable', 'error_code')
    safe['questions'] = Array(data['questions']).map { |q| q.slice('id', 'type', 'question', 'options') }
    render json: { success: true, data: safe }
  end

  def service_unavailable
    render json: { success: false, error: 'Listening service is unavailable. Check status before trying again.' }, status: :service_unavailable
  end
end
