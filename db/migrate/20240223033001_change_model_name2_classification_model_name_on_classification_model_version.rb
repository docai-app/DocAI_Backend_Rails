# frozen_string_literal: true

class ChangeModelName2ClassificationModelNameOnClassificationModelVersion < ActiveRecord::Migration[7.0]
  def change
    rename_column :classification_model_versions, :model_name, :classification_model_name
  end
end
