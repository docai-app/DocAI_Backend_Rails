class HardenOperationsDelivery < ActiveRecord::Migration[7.0]
  def up
    column = connection.columns(:essay_operation_events).find { |c| c.name == 'occurred_at' }
    unless column.sql_type.include?('with time zone') || column.sql_type == 'timestamptz'
      # The reporting migration is unreleased. Never guess the timezone of any
      # already collected legacy telemetry on a server that ran an earlier draft.
      raise 'Legacy report event timestamps need operator timezone review before migration' if select_value('SELECT COUNT(*) FROM essay_operation_events').to_i.positive?
      change_column :essay_operation_events, :occurred_at, :timestamptz, using: "occurred_at AT TIME ZONE 'UTC'"
    end
    require_relative '20260912001000_create_operations_reporting'
    CreateOperationsReporting.new.install_triggers
    create_table :essay_generation_notifications, id: :uuid do |t|
      t.references :essay_generation_run, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.uuid :token, null: false
      t.string :kind, null: false
      t.string :state, null: false, default: 'preparing'
      t.datetime :claimed_at
      t.datetime :sent_at
      t.string :failure_class
      t.timestamps
    end
    add_index :essay_generation_notifications, [:essay_generation_run_id, :token, :kind], unique: true, name: 'idx_generation_notification_identity'
  end

  def down
    drop_table :essay_generation_notifications
    # Keep offset-aware telemetry. Dropping its timezone would lose information.
  end
end
