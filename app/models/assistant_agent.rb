# == Schema Information
#
# Table name: public.assistant_agents
#
#  id             :bigint           not null, primary key
#  name           :string
#  description    :string
#  system_message :string
#  subdomain      :string
#  llm_config     :jsonb
#  meta           :jsonb
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  remark         :string
#  version        :string
#
class AssistantAgent < ApplicationRecord

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
    if production?
      previous_production = AssistantAgent.where(name: name, version: 'production')
                                      .where.not(id: id)
                                      .order(updated_at: :desc)
                                      .first
      previous_production.update(version: previous_production.updated_at.to_date.to_s) if previous_production
    end
  end

  def production?
    version == 'production'
  end

end
