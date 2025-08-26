# frozen_string_literal: true

class ChangeCommunitiesMetaNullable < ActiveRecord::Migration[7.0]
  def change
    change_column_null :communities, :meta, true
  end
end