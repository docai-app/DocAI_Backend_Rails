class CreateEssayGenerationRuns < ActiveRecord::Migration[7.0]
  def change
    create_table :essay_generation_runs, id: :uuid do |t|
      t.references :essay_grading, type: :uuid, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :state, null: false, default: 'queued'
      t.uuid :token, null: false
      t.integer :attempts, null: false, default: 0
      t.integer :manual_retries, null: false, default: 0
      t.jsonb :completed_stages, null: false, default: []
      t.string :failure_code
      t.datetime :queued_at
      t.datetime :started_at
      t.datetime :finished_at
      t.datetime :next_retry_at
      t.datetime :notified_at
      t.timestamps
    end
    add_index :essay_generation_runs, [:essay_grading_id, :kind], unique: true, name: 'idx_essay_generation_runs_unique_kind'
  end
end
