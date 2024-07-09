# frozen_string_literal: true

class ChangePrimaryKeyToUuidForGroups < ActiveRecord::Migration[7.0]
  def up
    # Add a new temporary UUID column
    add_column :groups, :uuid_id, :uuid, null: false

    # Populate the new uuid_id column with UUIDs
    Group.reset_column_information
    Group.find_each do |group|
      group.update_columns(uuid_id: SecureRandom.uuid)
    end

    # Remove the old primary key column
    remove_column :groups, :id

    # Rename the new UUID column to id
    rename_column :groups, :uuid_id, :id

    # Add a new primary key index to the id column
    execute 'ALTER TABLE groups ADD PRIMARY KEY (id);'
  end

  def down
    # Reverse of the above logic
    rename_column :groups, :id, :uuid_id
    add_column :groups, :id, :bigint, null: false, auto_increment: true
    Group.reset_column_information
    Group.find_each do |group|
      group.update_columns(id: group.uuid_id)
    end
    remove_column :groups, :uuid_id
    execute 'ALTER TABLE groups ADD PRIMARY KEY (id);'
  end
end
