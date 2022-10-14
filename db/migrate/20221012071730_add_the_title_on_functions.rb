class AddTheTitleOnFunctions < ActiveRecord::Migration[7.0]
  def change
    add_column :functions, :title, :string, null: false, default: ""
  end
end
