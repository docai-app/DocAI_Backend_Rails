class AddEssayGenerationRecovery < ActiveRecord::Migration[7.0]
  def change
    add_column :essay_generation_runs, :provider_context, :jsonb, null: false, default: {}
    add_column :essay_generation_runs, :recovery_version, :integer, null: false, default: 0
    add_column :essay_generation_runs, :recovery_count, :integer, null: false, default: 0
    add_column :essay_generation_runs, :resume_pending, :boolean, null: false, default: false
    add_column :essay_generation_runs, :missing_since, :datetime
    add_column :essay_generation_runs, :recovery_checked_at, :datetime
    add_column :essay_generation_runs, :attention_required_at, :datetime
    add_column :essay_generation_runs, :attention_notified_at, :datetime
    add_index :essay_generation_runs, [:state, :recovery_checked_at], name: 'idx_generation_recovery_scan'
  end
end
