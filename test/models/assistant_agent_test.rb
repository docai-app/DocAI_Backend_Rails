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
require 'test_helper'

class AssistantAgentTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
