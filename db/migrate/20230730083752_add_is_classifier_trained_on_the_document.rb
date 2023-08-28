# frozen_string_literal: true

class AddIsClassifierTrainedOnTheDocument < ActiveRecord::Migration[7.0]
  def change
    add_column :documents, :is_classifier_trained, :boolean, default: false
  end
end
