# frozen_string_literal: true

# == Schema Information
#
# Table name: public.agent_tools
#
#  id                 :bigint           not null, primary key
#  name               :string
#  invoke_name        :string
#  description        :string
#  invoke_description :string
#  category           :string
#  meta               :jsonb            not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
class AgentTool < ApplicationRecord
  def meta=(params)
    params = JSON.parse(params) if params.is_a?(String)
    super(params)
  end
end
