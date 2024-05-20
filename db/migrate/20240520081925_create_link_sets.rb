class CreateLinkSets < ActiveRecord::Migration[7.0]
  def change
    create_table :link_sets do |t|
      t.string :name
      t.timestamps
    end
  end
end
