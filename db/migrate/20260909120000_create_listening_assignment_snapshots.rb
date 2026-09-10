# frozen_string_literal: true

class CreateListeningAssignmentSnapshots < ActiveRecord::Migration[7.0]
  def change
    create_table :listening_assignment_snapshots, id: :uuid do |t|
      t.references :essay_assignment, type: :uuid, null: false, foreign_key: true, index: { unique: true }
      t.string :qg_version_id, null: false
      t.string :content_digest, null: false
      t.string :level, null: false
      t.jsonb :quiz, null: false
      t.text :plain_transcript, null: false
      t.text :audio_url, null: false
      t.jsonb :audio_metadata, null: false
      t.timestamps
    end
    add_check_constraint :listening_assignment_snapshots, "level IN ('A2', 'B2', 'C2')", name: 'listening_snapshot_level'
  end
end
