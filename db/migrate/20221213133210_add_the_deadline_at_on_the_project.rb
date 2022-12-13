class AddTheDeadlineAtOnTheProject < ActiveRecord::Migration[7.0]
  def change
    add_column :projects, :deadline_at, :timestamp, null: true, default: nil
  end
end
