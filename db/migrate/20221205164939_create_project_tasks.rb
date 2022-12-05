class CreateProjectTasks < ActiveRecord::Migration[7.0]
  def change
    create_table :project_tasks do |t|

      t.timestamps
    end
  end
end
