# frozen_string_literal: true

class CreateUserMailboxes < ActiveRecord::Migration[7.0]
  def change
    create_table :user_mailboxes, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.references :document, null: false, foreign_key: true, type: :uuid
      t.string :message_id
      t.string :subject
      t.string :sender
      t.string :recipient
      t.datetime :sent_at
      t.datetime :received_at
      t.jsonb :attachment, null: true
      t.text :content
      t.boolean :read, default: false

      t.timestamps
    end
  end
end
