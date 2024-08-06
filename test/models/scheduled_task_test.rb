# frozen_string_literal: true

# == Schema Information
#
# Table name: scheduled_tasks
#
#  name        :string
#  description :string
#  user_type   :string           not null
#  user_id     :uuid             not null
#  dag_id      :uuid
#  cron        :string
#  status      :integer          default("pending")
#  meta        :jsonb
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  entity_id   :uuid
#  one_time    :boolean          default(TRUE)
#  will_run_at :datetime
#  id          :uuid             not null, primary key
#
# Indexes
#
#  index_scheduled_tasks_on_dag_id     (dag_id)
#  index_scheduled_tasks_on_entity_id  (entity_id)
#  index_scheduled_tasks_on_user       (user_type,user_id)
#
require 'test_helper'

class ScheduledTaskTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end