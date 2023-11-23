# frozen_string_literal: true

class AddAirflowAcceptedToDagRun < ActiveRecord::Migration[7.0]
  def change
    add_column :dag_runs, :airflow_accepted, :boolean, default: false, null: false
    add_index :dag_runs, :airflow_accepted
  end
end
