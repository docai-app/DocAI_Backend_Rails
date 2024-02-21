# frozen_string_literal: true

# == Schema Information
#
# Table name: public.agent_tools
#
#  id                 :bigint(8)        not null, primary key
#  name               :string
#  invoke_name        :string
#  description        :string
#  invoke_description :string
#  category           :string
#  meta               :jsonb            not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
# Indexes
#
#  index_agent_tools_on_category  (category)
#
class AgentTool < ApplicationRecord
  def meta=(params)
    params = JSON.parse(params) if params.is_a?(String)
    super(params)
  end
end
