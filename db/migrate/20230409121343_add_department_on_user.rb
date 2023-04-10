class AddDepartmentOnUser < ActiveRecord::Migration[7.0]
  def change
    add_reference :users, :department, type: :uuid, foreign_key: true
  end
end
