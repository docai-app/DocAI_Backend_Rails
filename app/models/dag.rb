# frozen_string_literal: true

# == Schema Information
#
# Table name: dags
#
#  id         :uuid             not null, primary key
#  user_id    :uuid
#  dag_name   :string
#  dag_status :integer          default("pending")
#  meta       :jsonb
#  statistic  :jsonb
#  dag_meta   :jsonb
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
class Dag < ApplicationRecord
  belongs_to :user

  enum dag_status: { pending: 0, in_progress: 1, finish: 2 }
end
