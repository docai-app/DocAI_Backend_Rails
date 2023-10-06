# frozen_string_literal: true

class Dag < ApplicationRecord
  belongs_to :user

  enum dag_status: { pending: 0, in_progress: 1, finish: 2 }
end
