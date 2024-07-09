# frozen_string_literal: true

class AddDescriptionToLinkSet < ActiveRecord::Migration[7.0]
  def change
    add_column :link_sets, :description, :string
  end
end
