class AddTanentToDagRun < ActiveRecord::Migration[7.0]
  def change
    add_column :dag_runs, :tanent, :string
    add_index :dag_runs, :tanent
  end
end
