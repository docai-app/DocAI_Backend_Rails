class AddDifyTokenToChatbot < ActiveRecord::Migration[7.0]
  def change
    add_column :chatbots, :dify_token, :string
    add_index :chatbots, :dify_token
  end
end
