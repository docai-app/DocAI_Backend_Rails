# frozen_string_literal: true

class AddFileContentToGeneralUserFeed < ActiveRecord::Migration[7.0]
  def change
    add_column :general_user_feeds, :file_content, :text, null: true, default: nil
  end
end
