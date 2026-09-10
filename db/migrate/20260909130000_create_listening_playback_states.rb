# frozen_string_literal: true

class CreateListeningPlaybackStates < ActiveRecord::Migration[7.0]
  def change
    create_table :listening_playback_states, id: :uuid do |t|
      t.references :essay_assignment, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :general_user, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.integer :play_count, null: false, default: 0
      t.string :last_request_id
      t.datetime :last_issued_at
      t.timestamps
    end
    add_index :listening_playback_states, [:essay_assignment_id, :general_user_id],
      unique: true, name: 'listening_playback_assignment_user'
    add_check_constraint :listening_playback_states, 'play_count >= 0', name: 'listening_playback_count_nonnegative'
  end
end
