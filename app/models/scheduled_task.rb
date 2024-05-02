# frozen_string_literal: true

# == Schema Information
#
# Table name: public.scheduled_tasks
#
#  id          :bigint(8)        not null, primary key
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
#
# Indexes
#
#  index_scheduled_tasks_on_dag_id     (dag_id)
#  index_scheduled_tasks_on_entity_id  (entity_id)
#  index_scheduled_tasks_on_user       (user_type,user_id)
#
class ScheduledTask < ApplicationRecord
  belongs_to :user, polymorphic: true
  belongs_to :entity

  enum status: { pending: 0, in_progress: 1, finish: 2 }
end
