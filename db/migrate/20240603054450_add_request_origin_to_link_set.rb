# frozen_string_literal: true

class AddRequestOriginToLinkSet < ActiveRecord::Migration[7.0]
  def change
    add_column :link_sets, :request_origin, :string
    add_column :link_sets, :workspace, :string
    add_index :link_sets, :workspace
  end
end
