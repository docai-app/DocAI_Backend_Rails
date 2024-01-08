# frozen_string_literal: true

class AgentTool < ApplicationRecord
  def meta=(params)
    params = JSON.parse(params) if params.is_a?(String)
    super(params)
  end
end
