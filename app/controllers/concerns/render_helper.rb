# frozen_string_literal: true

# render_helper.rb
module RenderHelper
  extend ActiveSupport::Concern

  def render_ok(data: {}, message: 'ok', metadata: {}, code: 200, headers: {})
    @message = message
    @code = code
    @data = data
    @metadata = metadata
    headers.each do |header|
      response.set_header(header[0].to_s, header[1])
    end
    render template: 'templates/render_ok.json.jbuilder'
  end

  def render_errors(error_code, errors, code: 422)
    render_format({ error_code: }, nil, errors, code, false)
  end

  def render_errors!(exception, errors = nil)
    errors = if errors.nil?
               exception.errors
             else
               exception.message(errors)
             end

    raise 'Unknown Error' unless errors.present?

    render json: errors.merge({ success: false }),
           status: errors[:status]
  end

  def render_format(data, message, errors, code, success)
    render json: { message:, errors:, code:, success: }.merge(data),
           status: code
  end
end
