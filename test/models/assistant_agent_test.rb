# frozen_string_literal: true

# == Schema Information
#
# Table name: public.assistant_agents
#
#  id                          :bigint           not null, primary key
#  name                        :string
#  description                 :string
#  system_message              :string
#  subdomain                   :string
#  llm_config                  :jsonb
#  meta                        :jsonb
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  remark                      :string
#  version                     :string
#  name_en                     :string
#  prompt_header               :string
#  category                    :string
#  helper_agent_system_message :string
#
require 'test_helper'

class AssistantAgentTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
