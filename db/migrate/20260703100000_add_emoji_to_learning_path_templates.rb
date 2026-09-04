# frozen_string_literal: true

class AddEmojiToLearningPathTemplates < ActiveRecord::Migration[7.0]
  def change
    add_column :learning_path_templates, :emoji, :string
  end
end
