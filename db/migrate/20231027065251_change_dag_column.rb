# frozen_string_literal: true

class ChangeDagColumn < ActiveRecord::Migration[7.0]
  def change
    rename_column :dags, :dag_name, :name
    remove_column :dags, :dag_status
    remove_column :dags, :dag_meta
    remove_column :dags, :statistic
  end
end
