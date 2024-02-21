# frozen_string_literal: true

# == Schema Information
#
# Table name: public.assistant_agents
#
#  id                            :bigint(8)        not null, primary key
#  name                          :string
#  description                   :string
#  system_message                :string
#  subdomain                     :string
#  llm_config                    :jsonb
#  meta                          :jsonb
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#  remark                        :string
#  version                       :string
#  name_en                       :string
#  prompt_header                 :string
#  category                      :string
#  helper_agent_system_message   :string
#  conclude_conversation_message :string
#
# Indexes
#
#  index_assistant_agents_on_category  (category)
#  index_assistant_agents_on_name      (name)
#  index_assistant_agents_on_name_en   (name_en)
#  index_assistant_agents_on_version   (version)
#
class AssistantAgent < ApplicationRecord
  has_many :agent_use_tools
  has_many :agent_tools, through: :agent_use_tools

  def meta=(params)
    params = JSON.parse(params) if params.is_a?(String)
    super(params)
  end

  def llm_config=(params)
    params = JSON.parse(params) if params.is_a?(String)
    super(params)
  end

  before_save :update_previous_production

  def update_previous_production
    return unless production?

    previous_production = AssistantAgent.where(name:, version: 'production')
                                        .where.not(id:)
                                        .order(updated_at: :desc)
                                        .first
    previous_production&.update(version: previous_production.updated_at.to_date.to_s)
  end

  def production?
    version == 'production'
  end
end
